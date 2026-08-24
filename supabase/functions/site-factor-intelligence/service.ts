import {
  InvalidSiteFactorIntelligenceRequest,
  ProviderFailure,
  buildFixedOverpassQuery,
  buildRadiusPolygon,
  maximumProviderResponseBytes,
  overpassEndpoint,
  overpassTimeoutMs,
  parseBearerToken,
  parseBoundedSiteFactorIntelligenceRequest,
  parseOverpassEvidence,
  parseWorldPopPopulation,
  providerTimeoutMs,
  readBoundedUtf8Body,
  scoreOsmEvidence,
  toPublicResponse,
  worldPopDataYear,
  worldPopOverallTimeoutMs,
  worldPopPopulationEndpoint,
  worldPopTasksEndpoint,
  type ConfirmedEastMalaysiaTerritory,
  type SiteFactorIntelligenceRequest,
} from "./site_factor_intelligence.ts";

export type HttpClient = (url: string, init: RequestInit) => Promise<Response>;
export interface SiteValidator {
  validate(request: SiteFactorIntelligenceRequest, accessToken: string): Promise<{
    validationStatus: string;
    confirmedTerritory: ConfirmedEastMalaysiaTerritory | null;
  }>;
}
export interface SiteFactorIntelligenceDependencies {
  authenticate(accessToken: string): Promise<boolean>;
  validator: SiteValidator;
  http: HttpClient;
  now?: () => Date;
}
export interface SupabaseAuthDependencies { http: HttpClient; supabaseUrl: string; supabaseAnonKey: string; }
export class SiteNotValidatedInside extends Error {
  constructor() { super("The selected site is not confirmed inside East Malaysia."); this.name = "SiteNotValidatedInside"; }
}
export class AuthenticationUnavailable extends Error {
  constructor() { super("Supabase authentication is unavailable."); this.name = "AuthenticationUnavailable"; }
}

export async function verifySupabaseAccessToken(accessToken: string, dependencies: SupabaseAuthDependencies): Promise<boolean> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 5_000);
  try {
    const response = await dependencies.http(`${dependencies.supabaseUrl}/auth/v1/user`, {
      headers: { apikey: dependencies.supabaseAnonKey, authorization: `Bearer ${accessToken}` },
      signal: controller.signal,
    });
    if (response.status >= 500) throw new AuthenticationUnavailable();
    if (!response.ok) return false;
    const user = await response.json();
    if (user === null || typeof user !== "object" || Array.isArray(user)) throw new AuthenticationUnavailable();
    return true;
  } catch (error) {
    if (error instanceof AuthenticationUnavailable) throw error;
    throw new AuthenticationUnavailable();
  } finally { clearTimeout(timeout); }
}

export function createSiteFactorIntelligenceHandler(dependencies: SiteFactorIntelligenceDependencies): (request: Request) => Promise<Response> {
  return async (request) => {
    if (request.method !== "POST") return jsonResponse({ error: "method_not_allowed" }, 405, { Allow: "POST" });
    const accessToken = parseBearerToken(request.headers.get("authorization"));
    if (accessToken === null) return jsonResponse({ error: "unauthorized" }, 401);
    try {
      if (!(await dependencies.authenticate(accessToken))) return jsonResponse({ error: "unauthorized" }, 401);
    } catch (_) { return jsonResponse({ error: "authentication_unavailable" }, 503); }
    try {
      const candidate = await parseBoundedSiteFactorIntelligenceRequest(request);
      const validation = await dependencies.validator.validate(candidate, accessToken);
      if (validation.validationStatus !== "inside" || validation.confirmedTerritory === null) {
        throw new SiteNotValidatedInside();
      }
      const [populationResult, osmResult] = await Promise.allSettled([
        loadWorldPopPopulation(candidate, dependencies.http),
        loadOverpassEvidence(candidate, dependencies.http),
      ]);
      return jsonResponse(toPublicResponse(
        candidate,
        populationResult.status === "fulfilled" ? populationResult.value : null,
        osmResult.status === "fulfilled" ? osmResult.value : null,
        validation.confirmedTerritory,
        (dependencies.now ?? (() => new Date()))(),
      ));
    } catch (error) {
      if (error instanceof InvalidSiteFactorIntelligenceRequest) return jsonResponse({ error: "invalid_request" }, 400);
      if (error instanceof SiteNotValidatedInside) return jsonResponse({ error: "site_not_confirmed_inside" }, 403);
      return jsonResponse({ error: "service_unavailable" }, 503);
    }
  };
}

async function loadOverpassEvidence(request: SiteFactorIntelligenceRequest, http: HttpClient) {
  const payload = await fetchProviderJson(http, overpassEndpoint, {
    method: "POST",
    headers: {
      "content-type": "application/x-www-form-urlencoded;charset=UTF-8", accept: "application/json",
      "user-agent": "Smart Fuel Station Innovation/1.0 (+https://github.com/cj-yeu/smart_fuel_station_innovation)",
    },
    body: new URLSearchParams({ data: buildFixedOverpassQuery(request) }),
  }, undefined, overpassTimeoutMs);
  return scoreOsmEvidence(request, parseOverpassEvidence(payload));
}

async function loadWorldPopPopulation(request: SiteFactorIntelligenceRequest, http: HttpClient) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), worldPopOverallTimeoutMs);
  try {
    const submitted = await fetchProviderJson(http, worldPopPopulationEndpoint, {
      method: "POST", headers: { "content-type": "application/json", accept: "application/json" },
      body: JSON.stringify({ geojson: buildRadiusPolygon(request), year: worldPopDataYear, resolution: "100m" }),
    }, controller.signal);
    const taskId = parseTaskId(submitted);
    for (let attempt = 0; attempt < 6; attempt += 1) {
      await delay(300, controller.signal);
      const result = await fetchProviderJson(http, `${worldPopTasksEndpoint}/${encodeURIComponent(taskId)}`,
        { headers: { accept: "application/json" } }, controller.signal);
      if (isTaskPending(result)) continue;
      return parseWorldPopPopulation(result);
    }
    throw new ProviderFailure();
  } catch (_) { throw new ProviderFailure(); } finally { clearTimeout(timeout); }
}

async function fetchProviderJson(
  http: HttpClient,
  url: string,
  init: RequestInit,
  overallSignal?: AbortSignal,
  timeoutMs = providerTimeoutMs,
): Promise<unknown> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  const onAbort = () => controller.abort();
  overallSignal?.addEventListener("abort", onAbort, { once: true });
  try {
    const response = await http(url, { ...init, signal: controller.signal });
    if (!response.ok) throw new ProviderFailure();
    const text = await readBoundedUtf8Body(response.body, response.headers.get("content-length"),
      maximumProviderResponseBytes, () => new ProviderFailure(), controller.signal);
    return JSON.parse(text);
  } catch (_) { throw new ProviderFailure(); }
  finally { clearTimeout(timeout); overallSignal?.removeEventListener("abort", onAbort); }
}
function parseTaskId(value: unknown): string {
  if (value === null || typeof value !== "object" || Array.isArray(value)) throw new ProviderFailure();
  const taskId = (value as Record<string, unknown>).task_id;
  if (typeof taskId !== "string" || !/^[A-Za-z0-9-]+$/.test(taskId)) throw new ProviderFailure();
  return taskId;
}
function isTaskPending(value: unknown): boolean {
  return value !== null && typeof value === "object" && !Array.isArray(value) &&
    ["pending", "queued", "processing"].includes((value as Record<string, unknown>).status as string);
}
async function delay(milliseconds: number, signal: AbortSignal): Promise<void> {
  if (signal.aborted) throw new ProviderFailure();
  await new Promise<void>((resolve, reject) => {
    const timeout = setTimeout(resolve, milliseconds);
    signal.addEventListener("abort", () => { clearTimeout(timeout); reject(new ProviderFailure()); }, { once: true });
  });
}
function jsonResponse(value: Record<string, unknown>, status = 200, headers: HeadersInit = {}): Response {
  return new Response(JSON.stringify(value), { status, headers: { "content-type": "application/json", ...headers } });
}
