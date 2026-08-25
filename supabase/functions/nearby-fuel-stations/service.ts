import {
  InvalidNearbyFuelStationsRequest,
  type NearbyFuelStationsRequest,
  type NearbyFuelStationsResult,
  UpstreamFuelStationsFailure,
  buildFixedOverpassQuery,
  fallbackOverpassEndpoint,
  fallbackOverpassTimeoutMs,
  makeNearbyFuelStationsResult,
  maximumOverpassResponseBytes,
  overpassEndpoint,
  overpassTimeoutMs,
  parseBearerToken,
  parseBoundedNearbyFuelStationsRequest,
  parseOverpassFuelStations,
  readBoundedUtf8Body,
  toNearbyFuelStationsPublicResponse,
} from "./nearby_fuel_stations.ts";

export const overpassUserAgent =
  "Smart Fuel Station Innovation/1.0 (+https://github.com/cj-yeu/smart_fuel_station_innovation)";

export interface SiteValidator {
  validate(
    request: NearbyFuelStationsRequest,
    accessToken: string,
  ): Promise<{ validationStatus: string }>;
}

export interface FuelStationCache {
  get(request: NearbyFuelStationsRequest): Promise<NearbyFuelStationsResult | null>;
  put(
    request: NearbyFuelStationsRequest,
    result: NearbyFuelStationsResult,
    sourceResponse: unknown,
  ): Promise<NearbyFuelStationsResult>;
}

export type HttpClient = (
  url: string,
  init: RequestInit,
) => Promise<Response>;

export interface NearbyFuelStationsServiceDependencies {
  validator: SiteValidator;
  cache: FuelStationCache;
  http: HttpClient;
  now?: () => Date;
}

export interface SupabaseAuthDependencies {
  http: HttpClient;
  supabaseUrl: string;
  supabaseAnonKey: string;
  timeoutMs?: number;
}

export interface NearbyFuelStationsHandlerDependencies
  extends NearbyFuelStationsServiceDependencies {
  authenticate(accessToken: string): Promise<boolean>;
}

export class SiteNotValidatedInside extends Error {
  constructor() {
    super("The selected site is not confirmed inside East Malaysia.");
    this.name = "SiteNotValidatedInside";
  }
}

export class AuthenticationUnavailable extends Error {
  constructor() {
    super("Supabase authentication is unavailable.");
    this.name = "AuthenticationUnavailable";
  }
}

export async function verifySupabaseAccessToken(
  accessToken: string,
  dependencies: SupabaseAuthDependencies,
): Promise<boolean> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), dependencies.timeoutMs ?? 5_000);
  try {
    const response = await dependencies.http(`${dependencies.supabaseUrl}/auth/v1/user`, {
      headers: {
        apikey: dependencies.supabaseAnonKey,
        authorization: `Bearer ${accessToken}`,
      },
      signal: controller.signal,
    });
    if (response.status >= 500) throw new AuthenticationUnavailable();
    if (!response.ok) return false;
    const user = await response.json();
    if (user === null || typeof user !== "object" || Array.isArray(user)) {
      throw new AuthenticationUnavailable();
    }
    return true;
  } catch (error) {
    if (error instanceof AuthenticationUnavailable) throw error;
    throw new AuthenticationUnavailable();
  } finally {
    clearTimeout(timeout);
  }
}

export function createNearbyFuelStationsHandler(
  dependencies: NearbyFuelStationsHandlerDependencies,
): (request: Request) => Promise<Response> {
  return async (request) => {
    if (request.method !== "POST") {
      return jsonResponse({ error: "method_not_allowed" }, 405, { Allow: "POST" });
    }

    const accessToken = parseBearerToken(request.headers.get("authorization"));
    if (accessToken === null) return jsonResponse({ error: "unauthorized" }, 401);

    try {
      if (!(await dependencies.authenticate(accessToken))) {
        return jsonResponse({ error: "unauthorized" }, 401);
      }
    } catch (_) {
      return jsonResponse({ error: "authentication_unavailable" }, 503);
    }

    try {
      const nearbyRequest = await parseBoundedNearbyFuelStationsRequest(request);
      const result = await loadNearbyFuelStations(nearbyRequest, accessToken, dependencies);
      return jsonResponse(toNearbyFuelStationsPublicResponse(result));
    } catch (error) {
      if (error instanceof InvalidNearbyFuelStationsRequest) {
        return jsonResponse({ error: "invalid_request" }, 400);
      }
      if (error instanceof SiteNotValidatedInside) {
        return jsonResponse({ error: "site_not_confirmed_inside" }, 403);
      }
      if (error instanceof UpstreamFuelStationsFailure) {
        return jsonResponse({ error: "upstream_unavailable" }, 502);
      }
      return jsonResponse({ error: "service_unavailable" }, 503);
    }
  };
}

export async function loadNearbyFuelStations(
  request: NearbyFuelStationsRequest,
  accessToken: string,
  dependencies: NearbyFuelStationsServiceDependencies,
): Promise<NearbyFuelStationsResult> {
  const validation = await dependencies.validator.validate(request, accessToken);
  if (validation.validationStatus !== "inside") {
    throw new SiteNotValidatedInside();
  }

  let cached: NearbyFuelStationsResult | null = null;
  try {
    cached = await dependencies.cache.get(request);
  } catch (_) {
    // Cache availability must not prevent a validated fixed upstream request.
  }
  if (cached !== null) return cached;

  const payload = await fetchFixedOverpassPayload(dependencies.http, request);
  const stations = parseOverpassFuelStations(payload, request);
  const result = makeNearbyFuelStationsResult(
    request,
    stations,
    (dependencies.now ?? (() => new Date()))(),
  );
  try {
    return await dependencies.cache.put(request, result, payload);
  } catch (_) {
    // A cache/prune failure must not discard valid, normalized OSM evidence.
    return result;
  }
}

export async function fetchFixedOverpassPayload(
  http: HttpClient,
  request: NearbyFuelStationsRequest,
  timeoutMs = overpassTimeoutMs,
): Promise<unknown> {
  try {
    return await fetchOverpassPayloadFromEndpoint(
      http,
      request,
      overpassEndpoint,
      timeoutMs,
    );
  } catch (error) {
    // Tests and callers that supply a custom timeout are explicitly asking for
    // one bounded attempt. Production gets one fixed fallback endpoint.
    if (
      timeoutMs !== overpassTimeoutMs ||
      !(error instanceof UpstreamFuelStationsFailure) ||
      !error.retryable
    ) {
      throw error;
    }
    return fetchOverpassPayloadFromEndpoint(
      http,
      request,
      fallbackOverpassEndpoint,
      fallbackOverpassTimeoutMs,
    );
  }
}

async function fetchOverpassPayloadFromEndpoint(
  http: HttpClient,
  request: NearbyFuelStationsRequest,
  endpoint: string,
  timeoutMs: number,
): Promise<unknown> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await http(endpoint, {
      method: "POST",
      headers: {
        "content-type": "application/x-www-form-urlencoded;charset=UTF-8",
        accept: "application/json",
        "user-agent": overpassUserAgent,
      },
      body: new URLSearchParams({ data: buildFixedOverpassQuery(request) }),
      signal: controller.signal,
    });
    if (!response.ok) {
      throw new UpstreamFuelStationsFailure(
        undefined,
        { retryable: response.status === 429 || response.status >= 500 },
      );
    }
    const text = await readBoundedUtf8Body(
      response.body,
      response.headers.get("content-length"),
      maximumOverpassResponseBytes,
      () => new UpstreamFuelStationsFailure(undefined, { retryable: false }),
      controller.signal,
      () => controller.abort(),
    );
    try {
      return JSON.parse(text);
    } catch (_) {
      throw new UpstreamFuelStationsFailure(undefined, { retryable: false });
    }
  } catch (error) {
    if (error instanceof InvalidNearbyFuelStationsRequest) throw error;
    if (error instanceof UpstreamFuelStationsFailure) throw error;
    throw new UpstreamFuelStationsFailure();
  } finally {
    clearTimeout(timeout);
  }
}

function jsonResponse(
  value: Record<string, unknown>,
  status = 200,
  headers: HeadersInit = {},
): Response {
  return new Response(JSON.stringify(value), {
    status,
    headers: { "content-type": "application/json", ...headers },
  });
}
