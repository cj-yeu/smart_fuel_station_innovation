import {
  InvalidSiteFactorIntelligenceRequest,
  ProviderFailure,
  buildFixedOverpassQuery,
  buildRadiusPolygon,
  districtProviderTimeoutMs,
  geoBoundariesDistrictEndpoint,
  maximumProviderResponseBytes,
  fallbackOverpassEndpoint,
  fallbackOverpassTimeoutMs,
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
  type DistrictReference,
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
      const [populationResult, osmResult, districtReferenceResult] =
        await Promise.allSettled([
        loadWorldPopPopulation(candidate, dependencies.http),
        loadOverpassEvidence(candidate, dependencies.http),
        loadDistrictReference(candidate, validation.confirmedTerritory, dependencies.http),
        ]);
      return jsonResponse(toPublicResponse(
        candidate,
        populationResult.status === "fulfilled" ? populationResult.value : null,
        osmResult.status === "fulfilled" ? osmResult.value : null,
        validation.confirmedTerritory,
        districtReferenceResult.status === "fulfilled"
          ? districtReferenceResult.value
          : null,
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
  let payload: unknown;
  try {
    payload = await loadOverpassPayload(
      request,
      http,
      overpassEndpoint,
      overpassTimeoutMs,
    );
  } catch (_) {
    // Keep the request bounded and use just one server-owned fallback. This
    // preserves partial availability when either OSM provider is unavailable.
    payload = await loadOverpassPayload(
      request,
      http,
      fallbackOverpassEndpoint,
      fallbackOverpassTimeoutMs,
    );
  }
  return scoreOsmEvidence(request, parseOverpassEvidence(payload));
}

async function loadOverpassPayload(
  request: SiteFactorIntelligenceRequest,
  http: HttpClient,
  endpoint: string,
  timeoutMs: number,
): Promise<unknown> {
  return fetchProviderJson(http, endpoint, {
    method: "POST",
    headers: {
      "content-type": "application/x-www-form-urlencoded;charset=UTF-8", accept: "application/json",
      "user-agent": "Smart Fuel Station Innovation/1.0 (+https://github.com/cj-yeu/smart_fuel_station_innovation)",
    },
    body: new URLSearchParams({ data: buildFixedOverpassQuery(request) }),
  }, undefined, timeoutMs);
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

type DistrictPolygon = {
  name: string;
  territory: ConfirmedEastMalaysiaTerritory;
  polygons: [number, number][][][];
};

let cachedDistrictPolygons: Promise<DistrictPolygon[]> | null = null;

async function loadDistrictReference(
  request: SiteFactorIntelligenceRequest,
  territory: ConfirmedEastMalaysiaTerritory,
  http: HttpClient,
): Promise<DistrictReference | null> {
  const districts = await loadDistrictPolygons(http);
  const matches = districts.filter((district) =>
    district.territory === territory &&
    isPointInDistrict(request.longitude, request.latitude, district.polygons)
  );
  return matches.length === 1
    ? { name: matches[0].name, territory: matches[0].territory }
    : null;
}

function loadDistrictPolygons(http: HttpClient): Promise<DistrictPolygon[]> {
  if (cachedDistrictPolygons === null) {
    cachedDistrictPolygons = fetchProviderJson(http, geoBoundariesDistrictEndpoint, {
      headers: { accept: "application/geo+json, application/json" },
    }, undefined, districtProviderTimeoutMs).then(parseDistrictPolygons).catch((error) => {
      cachedDistrictPolygons = null;
      throw error;
    });
  }
  return cachedDistrictPolygons;
}

function parseDistrictPolygons(value: unknown): DistrictPolygon[] {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new ProviderFailure();
  }
  const features = (value as Record<string, unknown>).features;
  if (!Array.isArray(features) || features.length < 1 || features.length > 200) {
    throw new ProviderFailure();
  }
  const districts: DistrictPolygon[] = [];
  for (const feature of features) {
    const district = parseDistrictPolygon(feature);
    if (district !== null) districts.push(district);
  }
  if (districts.length < 68) throw new ProviderFailure();
  return districts.sort((first, second) => first.name.localeCompare(second.name));
}

function parseDistrictPolygon(value: unknown): DistrictPolygon | null {
  if (value === null || typeof value !== "object" || Array.isArray(value)) return null;
  const feature = value as Record<string, unknown>;
  const properties = feature.properties;
  const geometry = feature.geometry;
  if (properties === null || typeof properties !== "object" || Array.isArray(properties) ||
    geometry === null || typeof geometry !== "object" || Array.isArray(geometry)) return null;
  const name = (properties as Record<string, unknown>).shapeName;
  const geometryRecord = geometry as Record<string, unknown>;
  if (typeof name !== "string" || name.trim() === "") return null;
  const territory = territoryForDistrictName(name);
  const polygons = geometryRecord.type === "Polygon"
    ? parsePolygon(geometryRecord.coordinates)
    : geometryRecord.type === "MultiPolygon"
    ? parseMultiPolygon(geometryRecord.coordinates)
    : null;
  if (territory === null || polygons === null) return null;
  return { name: normaliseDistrictName(name), territory, polygons };
}

function parseMultiPolygon(value: unknown): [number, number][][][] | null {
  if (!Array.isArray(value)) return null;
  const polygons: [number, number][][][] = [];
  for (const polygon of value) {
    const parsed = parsePolygon(polygon);
    if (parsed === null) return null;
    polygons.push(...parsed);
  }
  return polygons.length === 0 ? null : polygons;
}

function parsePolygon(value: unknown): [number, number][][][] | null {
  if (!Array.isArray(value) || value.length === 0) return null;
  const rings: [number, number][][] = [];
  for (const ringValue of value) {
    if (!Array.isArray(ringValue) || ringValue.length < 4) return null;
    const ring: [number, number][] = [];
    for (const pointValue of ringValue) {
      if (!Array.isArray(pointValue) || pointValue.length < 2 ||
        typeof pointValue[0] !== "number" || typeof pointValue[1] !== "number" ||
        !Number.isFinite(pointValue[0]) || !Number.isFinite(pointValue[1])) return null;
      ring.push([pointValue[0], pointValue[1]]);
    }
    rings.push(ring);
  }
  return [rings];
}

function isPointInDistrict(
  longitude: number,
  latitude: number,
  polygons: [number, number][][][],
): boolean {
  return polygons.some((polygon) =>
    isPointInRing(longitude, latitude, polygon[0]) &&
    !polygon.slice(1).some((ring) => isPointInRing(longitude, latitude, ring))
  );
}

function isPointInRing(longitude: number, latitude: number, ring: [number, number][]): boolean {
  let inside = false;
  for (let current = 0, previous = ring.length - 1; current < ring.length; previous = current++) {
    const [currentLongitude, currentLatitude] = ring[current];
    const [previousLongitude, previousLatitude] = ring[previous];
    const intersects = (currentLatitude > latitude) !== (previousLatitude > latitude) &&
      longitude < (previousLongitude - currentLongitude) * (latitude - currentLatitude) /
        (previousLatitude - currentLatitude) + currentLongitude;
    if (intersects) inside = !inside;
  }
  return inside;
}

function territoryForDistrictName(name: string): ConfirmedEastMalaysiaTerritory | null {
  if (sabahDistrictNames.has(name)) return "sabah";
  if (sarawakDistrictNames.has(name)) return "sarawak";
  return name === "Labuan" ? "labuan" : null;
}

function normaliseDistrictName(name: string): string {
  return name === "Nabawan / Persiangan" ? "Nabawan" :
    name === "Labuan" ? "W.P. Labuan" : name;
}

const sabahDistrictNames = new Set([
  "Beaufort", "Beluran", "Kalabakan", "Keningau", "Kinabatangan", "Kota Belud",
  "Kota Kinabalu", "Kota Marudu", "Kuala Penyu", "Kudat", "Kunak", "Lahad Datu",
  "Nabawan / Persiangan", "Papar", "Penampang", "Pitas", "Putatan", "Ranau",
  "Sandakan", "Semporna", "Sipitang", "Tambunan", "Tawau", "Telupid", "Tenom",
  "Tongod", "Tuaran",
]);
const sarawakDistrictNames = new Set([
  "Asajaya", "Bau", "Belaga", "Beluru", "Betong", "Bintulu", "Bukit Mabong",
  "Dalat", "Daro", "Julau", "Kabong", "Kanowit", "Kapit", "Kuching", "Lawas",
  "Limbang", "Lubok Antu", "Lundu", "Maradong", "Marudi", "Matu", "Miri", "Mukah",
  "Pakan", "Pusa", "Samarahan", "Saratok", "Sarikei", "Sebauh", "Selangau", "Serian",
  "Sibu", "Simunjan", "Song", "Sri Aman", "Subis", "Tanjung Manis", "Tatau", "Tebedu",
  "Telang Usan",
]);

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
