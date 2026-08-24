export const supportedAnalysisRadiiKm = [3, 5, 10] as const;
export const overpassEndpoint = "https://overpass-api.de/api/interpreter";
export const worldPopPopulationEndpoint = "https://api.worldpop.org/v2/population";
export const worldPopTasksEndpoint = "https://api.worldpop.org/v2/tasks";
export const worldPopDataYear = 2026;
export const maximumRequestBodyBytes = 4_096;
export const maximumProviderResponseBytes = 2 * 1_024 * 1_024;
export const maximumOsmElementCount = 5_000;
export const providerTimeoutMs = 8_000;
// Overpass accepts the fixed query with a 25-second server timeout.  Public
// instances can queue before processing, so this remains bounded while not
// discarding a valid response prematurely.
export const overpassTimeoutMs = 30_000;
export const worldPopOverallTimeoutMs = 18_000;
export const openStreetMapAttribution = "© OpenStreetMap contributors";
export const openStreetMapAttributionUrl = "https://www.openstreetmap.org/copyright";
export const worldPopAttribution = "WorldPop, University of Southampton";
export const worldPopAttributionUrl = "https://hub.worldpop.org/";
export const geoBoundariesDistrictEndpoint =
  "https://github.com/wmgeolab/geoBoundaries/raw/9469f09/releaseData/gbOpen/MYS/ADM2/geoBoundaries-MYS-ADM2.geojson";
export const geoBoundariesDistrictSource = "geoBoundaries MYS ADM2";
export const geoBoundariesDistrictSourceUrl =
  "https://www.geoboundaries.org/api/current/gbOpen/MYS/ADM2/";
export const geoBoundariesDistrictLicence = "CC BY 3.0";
export const districtProviderTimeoutMs = 12_000;

export interface SiteFactorIntelligenceRequest {
  latitude: number;
  longitude: number;
  analysisRadiusKm: 3 | 5 | 10;
}

export type ConfirmedEastMalaysiaTerritory = "sabah" | "sarawak" | "labuan";

export interface DistrictReference {
  name: string;
  territory: ConfirmedEastMalaysiaTerritory;
}

export type OsmType = "node" | "way" | "relation";
export interface Coordinate { latitude: number; longitude: number; }
export interface OsmEvidence {
  type: OsmType;
  id: string;
  tags: Record<string, string>;
  geometry: Coordinate[];
}
export interface PopulationEvidence {
  estimatedPopulation: number;
  densityPerSqKm: number;
  suggestedLevel: number;
  dataYear: number;
}
export interface OsmFactorEvidence {
  roadAccessibility: { nearestUsableRoadM: number | null; majorRoadCount: number; suggestedScore: number };
  commercialActivity: { commercialPoiCount: number; commercialLanduseCount: number; suggestedScore: number };
  residentialActivity: { residentialFeatureCount: number; residentialLanduseCount: number; suggestedScore: number };
  landAccessibility: {
    nearestAccessRoadM: number | null;
    restrictedAccessFeatureCount: number;
    suggestedScore: number;
  };
}

export class InvalidSiteFactorIntelligenceRequest extends Error {
  constructor() {
    super("Invalid site-factor-intelligence request.");
    this.name = "InvalidSiteFactorIntelligenceRequest";
  }
}
export class ProviderFailure extends Error {
  constructor() { super("Provider unavailable."); this.name = "ProviderFailure"; }
}

export function parseSiteFactorIntelligenceRequest(value: unknown): SiteFactorIntelligenceRequest {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new InvalidSiteFactorIntelligenceRequest();
  }
  const record = value as Record<string, unknown>;
  const keys = Object.keys(record).sort();
  const expected = ["analysis_radius_km", "latitude", "longitude"];
  if (keys.length !== expected.length || keys.some((key, index) => key !== expected[index]) ||
    typeof record.latitude !== "number" || typeof record.longitude !== "number" ||
    typeof record.analysis_radius_km !== "number") {
    throw new InvalidSiteFactorIntelligenceRequest();
  }
  return validateSiteFactorIntelligenceRequest({
    latitude: record.latitude,
    longitude: record.longitude,
    analysisRadiusKm: record.analysis_radius_km,
  });
}

export function parseSiteFactorIntelligenceRequestJson(rawJson: string): SiteFactorIntelligenceRequest {
  const cursor = new ExactJsonCursor(rawJson);
  const record = cursor.readExactNumericObject();
  cursor.requireEnd();
  return parseSiteFactorIntelligenceRequest(record);
}

export async function parseBoundedSiteFactorIntelligenceRequest(request: Request): Promise<SiteFactorIntelligenceRequest> {
  const rawJson = await readBoundedUtf8Body(
    request.body, request.headers.get("content-length"), maximumRequestBodyBytes,
    () => new InvalidSiteFactorIntelligenceRequest(),
  );
  return parseSiteFactorIntelligenceRequestJson(rawJson);
}

export function validateSiteFactorIntelligenceRequest(value: {
  latitude: number; longitude: number; analysisRadiusKm: number;
}): SiteFactorIntelligenceRequest {
  if (!Number.isFinite(value.latitude) || value.latitude < -90 || value.latitude > 90 ||
    !Number.isFinite(value.longitude) || value.longitude < -180 || value.longitude > 180 ||
    !Number.isFinite(value.analysisRadiusKm) ||
    !supportedAnalysisRadiiKm.includes(value.analysisRadiusKm as 3 | 5 | 10)) {
    throw new InvalidSiteFactorIntelligenceRequest();
  }
  return {
    latitude: normalizeCoordinate(value.latitude),
    longitude: normalizeCoordinate(value.longitude),
    analysisRadiusKm: value.analysisRadiusKm as 3 | 5 | 10,
  };
}

/** One fixed, server-owned OSM request. No caller-controlled query or provider URL. */
export function buildFixedOverpassQuery(request: SiteFactorIntelligenceRequest): string {
  const radiusMetres = request.analysisRadiusKm * 1000;
  const roadSearchMetres = Math.min(radiusMetres, 2_000);
  const around = `${radiusMetres},${request.latitude},${request.longitude}`;
  const roadAround = `${roadSearchMetres},${request.latitude},${request.longitude}`;
  return `[out:json][timeout:15][maxsize:1048576];
way(around:${roadAround})["highway"~"^(motorway|trunk|primary|secondary|tertiary|service|track)(_link)?$"]->.roads;
(
  nwr(around:${around})[shop]; nwr(around:${around})[office];
  nwr(around:${around})[amenity]; nwr(around:${around})[tourism];
  nwr(around:${around})["landuse"~"^(retail|commercial|industrial)$"];
  nwr(around:${around})["building"~"^(residential|apartments|house|detached)$"];
  nwr(around:${around})["landuse"="residential"];
  nwr(around:${around})["place"="neighbourhood"];
)->.context;
.roads out geom tags;
.context out center tags;`;
}

export function parseOverpassEvidence(payload: unknown): OsmEvidence[] {
  if (payload === null || typeof payload !== "object" || Array.isArray(payload) ||
    !Array.isArray((payload as Record<string, unknown>).elements)) throw new ProviderFailure();
  const values = (payload as { elements: unknown[] }).elements;
  if (values.length > maximumOsmElementCount) throw new ProviderFailure();
  const deduplicated = new Map<string, OsmEvidence>();
  for (const value of values) {
    const evidence = parseOsmEvidence(value);
    if (evidence !== null) deduplicated.set(`${evidence.type}:${evidence.id}`, evidence);
  }
  return [...deduplicated.values()].sort(compareOsmEvidence);
}

export function scoreOsmEvidence(request: SiteFactorIntelligenceRequest, evidence: OsmEvidence[]): OsmFactorEvidence {
  const roads = evidence.filter((item) => item.tags.highway !== undefined);
  const usableRoads = roads.filter(isUsableRoad);
  const nearestUsableRoadM = minimumRoadDistanceMetres(request, usableRoads);
  const roadScores = usableRoads.map((road) => roadAccessibilityScore(
    road.tags.highway!, minimumRoadDistanceMetres(request, [road]),
  ));
  const commercialPoiCount = evidence.filter(isCommercialPoi).length;
  const commercialLanduseCount = evidence.filter(isCommercialLanduse).length;
  const residentialFeatureCount = evidence.filter(isResidentialFeature).length;
  const residentialLanduseCount = evidence.filter(isResidentialLanduse).length;
  const restrictedAccessFeatureCount = roads.filter(isRestrictedRoad).length;
  const areaKmSquared = Math.PI * request.analysisRadiusKm ** 2;
  const commercialDensityPerTenKmSquared =
    (commercialPoiCount + commercialLanduseCount * 0.5) / areaKmSquared * 10;
  const residentialDensityPerSqKm =
    (residentialFeatureCount + residentialLanduseCount * 0.25) / areaKmSquared;
  return {
    roadAccessibility: {
      nearestUsableRoadM: nearestUsableRoadM === null ? null : round(nearestUsableRoadM, 1),
      majorRoadCount: usableRoads.filter(isMajorRoad).length,
      suggestedScore: roadScores.length === 0 ? 1 : Math.max(...roadScores),
    },
    commercialActivity: { commercialPoiCount, commercialLanduseCount, suggestedScore: commercialScore(commercialDensityPerTenKmSquared) },
    residentialActivity: { residentialFeatureCount, residentialLanduseCount, suggestedScore: residentialScore(residentialDensityPerSqKm) },
    landAccessibility: {
      nearestAccessRoadM: nearestUsableRoadM === null ? null : round(nearestUsableRoadM, 1),
      restrictedAccessFeatureCount,
      suggestedScore: landAccessibilityProxyScore(
        nearestUsableRoadM,
        restrictedAccessFeatureCount,
      ),
    },
  };
}

export function parseWorldPopPopulation(payload: unknown): PopulationEvidence {
  if (payload === null || typeof payload !== "object" || Array.isArray(payload)) throw new ProviderFailure();
  const record = payload as Record<string, unknown>;
  const result = record.result;
  if (record.status !== "success" || result === null || typeof result !== "object" || Array.isArray(result)) {
    throw new ProviderFailure();
  }
  const values = result as Record<string, unknown>;
  if (!isFiniteNonNegativeNumber(values.total_population) ||
    !isFiniteNonNegativeNumber(values.population_density) ||
    values.data_year !== worldPopDataYear) {
    throw new ProviderFailure();
  }
  return {
    estimatedPopulation: round(values.total_population, 0),
    densityPerSqKm: round(values.population_density, 2),
    suggestedLevel: populationLevel(values.population_density),
    dataYear: values.data_year,
  };
}

export function buildRadiusPolygon(request: SiteFactorIntelligenceRequest, segments = 64): Record<string, unknown> {
  const earthRadiusMetres = 6_371_008.8;
  const angularDistance = request.analysisRadiusKm * 1000 / earthRadiusMetres;
  const latitudeRadians = toRadians(request.latitude);
  const longitudeRadians = toRadians(request.longitude);
  const coordinates: number[][] = [];
  for (let index = 0; index <= segments; index += 1) {
    const bearing = 2 * Math.PI * (index % segments) / segments;
    const latitude = Math.asin(Math.sin(latitudeRadians) * Math.cos(angularDistance) +
      Math.cos(latitudeRadians) * Math.sin(angularDistance) * Math.cos(bearing));
    const longitude = longitudeRadians + Math.atan2(
      Math.sin(bearing) * Math.sin(angularDistance) * Math.cos(latitudeRadians),
      Math.cos(angularDistance) - Math.sin(latitudeRadians) * Math.sin(latitude),
    );
    coordinates.push([toDegrees(longitude), toDegrees(latitude)]);
  }
  return { type: "Polygon", coordinates: [coordinates] };
}

export function makeUnavailablePopulation(): Record<string, unknown> {
  return { available: false, estimated_population: null, density_per_sq_km: null,
    suggested_level: null, source: null, data_year: null, confidence: "medium" };
}
export function makeUnavailableOsmFactor(kind: "road" | "commercial" | "residential" | "land"): Record<string, unknown> {
  const common = { available: false, source: null, fetched_at: null };
  if (kind === "road") return { ...common, nearest_usable_road_m: null, major_road_count: null, suggested_score: null, confidence: "medium" };
  if (kind === "commercial") return { ...common, commercial_poi_count: null, commercial_landuse_count: null, suggested_score: null, confidence: "medium" };
  if (kind === "residential") return { ...common, residential_feature_count: null, residential_landuse_count: null, suggested_score: null, confidence: "low" };
  return { ...common, nearest_access_road_m: null, restricted_access_feature_count: null, suggested_score: null, confidence: "low" };
}

/**
 * A manually refreshed, regional registration-channel proxy derived from the
 * official JPJ transaction CSV. It is intentionally not a count of vehicles
 * located near the candidate or within the analysis radius.
 */
export function makeVehicleRegistrationProxy(
  territory: ConfirmedEastMalaysiaTerritory,
): Record<string, unknown> | null {
  const value = {
    sabah: 15_710,
    sarawak: 17_621,
    // The official CSV contains no Labuan-channel registrations in this
    // reporting period, so a zero must not be used as a local-demand estimate.
    labuan: null,
  }[territory];
  if (value === null) return null;
  const territoryLabel = territory === "sabah" ? "Sabah" : "Sarawak";
  return {
    available: true,
    value,
    geographic_scope: `${territoryLabel} JPJ registration-office/channel records`,
    data_period: "2026-01-01 to 2026-07-31",
    is_proxy: true,
    source: "JPJ vehicle-registration transactions via data.gov.my",
  };
}

export function toPublicResponse(
  request: SiteFactorIntelligenceRequest, population: PopulationEvidence | null,
  osm: OsmFactorEvidence | null,
  confirmedTerritory: ConfirmedEastMalaysiaTerritory,
  district: DistrictReference | null,
  fetchedAt: Date,
): Record<string, unknown> {
  const osmSource = { source: "OpenStreetMap via Overpass API", fetched_at: fetchedAt.toISOString() };
  const vehicleDemand = makeVehicleRegistrationProxy(confirmedTerritory);
  return {
    candidate: {
      latitude: request.latitude,
      longitude: request.longitude,
      analysis_radius_km: request.analysisRadiusKm,
      district_reference: district === null ? null : {
        name: district.name,
        source: geoBoundariesDistrictSource,
        source_url: geoBoundariesDistrictSourceUrl,
        licence: geoBoundariesDistrictLicence,
      },
    },
    population: population === null ? makeUnavailablePopulation() : {
      available: true, estimated_population: population.estimatedPopulation,
      density_per_sq_km: population.densityPerSqKm, suggested_level: population.suggestedLevel,
      source: "WorldPop Global2 Population Data", data_year: population.dataYear, confidence: "medium",
    },
    road_accessibility: osm === null ? makeUnavailableOsmFactor("road") : {
      available: true, ...osmSource, nearest_usable_road_m: osm.roadAccessibility.nearestUsableRoadM,
      major_road_count: osm.roadAccessibility.majorRoadCount,
      suggested_score: osm.roadAccessibility.suggestedScore, confidence: "medium",
    },
    commercial_activity: osm === null ? makeUnavailableOsmFactor("commercial") : {
      available: true, ...osmSource, commercial_poi_count: osm.commercialActivity.commercialPoiCount,
      commercial_landuse_count: osm.commercialActivity.commercialLanduseCount,
      suggested_score: osm.commercialActivity.suggestedScore, confidence: "medium",
    },
    residential_activity: osm === null ? makeUnavailableOsmFactor("residential") : {
      available: true, ...osmSource, residential_feature_count: osm.residentialActivity.residentialFeatureCount,
      residential_landuse_count: osm.residentialActivity.residentialLanduseCount,
      suggested_score: osm.residentialActivity.suggestedScore, confidence: "low",
    },
    // OSM cannot prove ownership, planning permission, legal access, easements, or availability.
    land_accessibility: osm === null ? makeUnavailableOsmFactor("land") : {
      available: true, ...osmSource, nearest_access_road_m: osm.landAccessibility.nearestAccessRoadM,
      restricted_access_feature_count: osm.landAccessibility.restrictedAccessFeatureCount,
      // A proximity/restriction proxy only; this never represents title,
      // permission, easements, legal access, or site availability.
      suggested_score: osm.landAccessibility.suggestedScore, confidence: "low",
    },
    // JPJ state is a registration office/channel field, never candidate-radius
    // demand or a count of vehicles located at this site.
    vehicle_demand: vehicleDemand ?? {
      available: false, value: null, geographic_scope: null, data_period: null,
      is_proxy: true, source: null,
    },
    attribution: [
      ...(population === null ? [] : [{ source: worldPopAttribution, url: worldPopAttributionUrl, licence: "CC BY 4.0" }]),
      ...(osm === null ? [] : [{ source: openStreetMapAttribution, url: openStreetMapAttributionUrl, licence: "ODbL" }]),
      ...(vehicleDemand === null ? [] : [{ source: "JPJ via data.gov.my", url: "https://storage.data.gov.my/transportation/vehicles_2026.csv", licence: "CC BY 4.0" }]),
      ...(district === null ? [] : [{ source: geoBoundariesDistrictSource, url: geoBoundariesDistrictSourceUrl, licence: geoBoundariesDistrictLicence }]),
    ],
  };
}

export function parseBearerToken(value: string | null): string | null {
  if (value === null) return null;
  const match = /^Bearer\s+(.+)$/i.exec(value);
  return match?.[1]?.trim() || null;
}

export async function readBoundedUtf8Body(
  body: ReadableStream<Uint8Array> | null, contentLength: string | null,
  maximumBytes: number, createError: () => Error, signal?: AbortSignal,
): Promise<string> {
  if (body === null || !Number.isSafeInteger(maximumBytes) || maximumBytes < 1) throw createError();
  if (declaredLengthExceedsLimit(contentLength, maximumBytes)) {
    await body.cancel().catch(() => undefined);
    throw createError();
  }
  const reader = body.getReader();
  const chunks: Uint8Array[] = [];
  let totalBytes = 0;
  try {
    while (true) {
      const next = await readAbortableChunk(reader, signal);
      if (next.done) break;
      totalBytes += next.value.byteLength;
      if (totalBytes > maximumBytes) throw createError();
      chunks.push(next.value);
    }
  } catch (_) {
    await reader.cancel().catch(() => undefined);
    throw createError();
  } finally { reader.releaseLock(); }
  const bytes = new Uint8Array(totalBytes);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  try { return new TextDecoder("utf-8", { fatal: true }).decode(bytes); }
  catch (_) { throw createError(); }
}

function parseOsmEvidence(value: unknown): OsmEvidence | null {
  if (value === null || typeof value !== "object" || Array.isArray(value)) return null;
  const record = value as Record<string, unknown>;
  const type = record.type;
  const id = parseOsmId(record.id);
  if ((type !== "node" && type !== "way" && type !== "relation") || id === null) return null;
  const tags = parseTags(record.tags);
  const geometry = parseGeometry(record.geometry) ?? parseCenter(record.center) ??
    (type === "node" ? parseCenter(record) : null);
  return geometry === null ? null : { type, id, tags, geometry };
}
function parseTags(value: unknown): Record<string, string> {
  if (value === null || typeof value !== "object" || Array.isArray(value)) return {};
  return Object.fromEntries(Object.entries(value as Record<string, unknown>)
    .filter((entry): entry is [string, string] => typeof entry[1] === "string")
    .sort(([first], [second]) => first.localeCompare(second)));
}
function parseGeometry(value: unknown): Coordinate[] | null {
  if (!Array.isArray(value) || value.length === 0) return null;
  const coordinates = value.map(parseCoordinate).filter((coordinate): coordinate is Coordinate => coordinate !== null);
  return coordinates.length === value.length ? coordinates : null;
}
function parseCenter(value: unknown): Coordinate[] | null {
  const coordinate = parseCoordinate(value);
  return coordinate === null ? null : [coordinate];
}
function parseCoordinate(value: unknown): Coordinate | null {
  if (value === null || typeof value !== "object" || Array.isArray(value)) return null;
  const record = value as Record<string, unknown>;
  if (!isFiniteCoordinate(record.lat, -90, 90) || !isFiniteCoordinate(record.lon, -180, 180)) return null;
  return { latitude: record.lat, longitude: record.lon };
}
function isUsableRoad(road: OsmEvidence): boolean {
  return [road.tags.access, road.tags.vehicle, road.tags.motor_vehicle]
    .every((value) => value !== "no" && value !== "private");
}
function isRestrictedRoad(road: OsmEvidence): boolean {
  return [road.tags.access, road.tags.vehicle, road.tags.motor_vehicle]
    .some((value) => value === "no" || value === "private");
}
function isMajorRoad(road: OsmEvidence): boolean {
  return /^(motorway|trunk|primary|secondary|tertiary)(_link)?$/.test(road.tags.highway ?? "");
}
function isCommercialPoi(item: OsmEvidence): boolean {
  return item.tags.shop !== undefined || item.tags.office !== undefined || item.tags.amenity !== undefined || item.tags.tourism !== undefined;
}
function isCommercialLanduse(item: OsmEvidence): boolean {
  return ["retail", "commercial", "industrial"].includes(item.tags.landuse ?? "");
}
function isResidentialFeature(item: OsmEvidence): boolean {
  return ["residential", "apartments", "house", "detached"].includes(item.tags.building ?? "") || item.tags.place === "neighbourhood";
}
function isResidentialLanduse(item: OsmEvidence): boolean { return item.tags.landuse === "residential"; }
function roadAccessibilityScore(highway: string, distanceMetres: number | null): number {
  if (distanceMetres === null) return 1;
  const base = highway.startsWith("motorway") || highway.startsWith("trunk") ? 5
    : highway.startsWith("primary") ? 4 : highway.startsWith("secondary") ? 3
    : highway.startsWith("tertiary") ? 2 : 1;
  const penalty = distanceMetres <= 50 ? 0 : distanceMetres <= 150 ? 1
    : distanceMetres <= 500 ? 2 : distanceMetres <= 2_000 ? 3 : 4;
  return clampInteger(base - penalty, 1, 5);
}
function commercialScore(density: number): number { return density < 2 ? 1 : density < 5 ? 2 : density < 10 ? 3 : density < 20 ? 4 : 5; }
function residentialScore(density: number): number { return density < 5 ? 1 : density < 20 ? 2 : density < 50 ? 3 : density < 150 ? 4 : 5; }
function landAccessibilityProxyScore(
  nearestRoadMetres: number | null,
  restrictedRoadCount: number,
): number {
  if (nearestRoadMetres === null) return 1;
  const distanceScore = nearestRoadMetres <= 100 ? 5
    : nearestRoadMetres <= 250 ? 4
    : nearestRoadMetres <= 500 ? 3
    : nearestRoadMetres <= 1_000 ? 2 : 1;
  // Nearby private/no-access road features reduce the confidence of physical
  // approach only. They are not evidence about the legal status of the site.
  return clampInteger(distanceScore - (restrictedRoadCount > 0 ? 1 : 0), 1, 5);
}
function populationLevel(density: number): number { return density < 2_000 ? 1 : density < 4_000 ? 2 : density < 6_000 ? 3 : density < 8_000 ? 4 : 5; }
function minimumRoadDistanceMetres(request: SiteFactorIntelligenceRequest, roads: OsmEvidence[]): number | null {
  let closest = Number.POSITIVE_INFINITY;
  for (const road of roads) {
    const distance = pointToPathDistanceMetres(request, road.geometry);
    if (distance !== null) closest = Math.min(closest, distance);
  }
  return Number.isFinite(closest) ? closest : null;
}
function pointToPathDistanceMetres(point: Coordinate, path: Coordinate[]): number | null {
  if (path.length === 0) return null;
  if (path.length === 1) return haversineDistanceMetres(point, path[0]);
  let closest = Number.POSITIVE_INFINITY;
  for (let index = 1; index < path.length; index += 1) {
    closest = Math.min(closest, pointToSegmentDistanceMetres(point, path[index - 1], path[index]));
  }
  return Number.isFinite(closest) ? closest : null;
}
function pointToSegmentDistanceMetres(point: Coordinate, start: Coordinate, end: Coordinate): number {
  const latitudeScale = 111_320;
  const longitudeScale = latitudeScale * Math.cos(toRadians(point.latitude));
  const startX = (start.longitude - point.longitude) * longitudeScale;
  const startY = (start.latitude - point.latitude) * latitudeScale;
  const endX = (end.longitude - point.longitude) * longitudeScale;
  const endY = (end.latitude - point.latitude) * latitudeScale;
  const deltaX = endX - startX;
  const deltaY = endY - startY;
  const lengthSquared = deltaX ** 2 + deltaY ** 2;
  if (lengthSquared === 0) return Math.hypot(startX, startY);
  const fraction = Math.max(0, Math.min(1, -(startX * deltaX + startY * deltaY) / lengthSquared));
  return Math.hypot(startX + fraction * deltaX, startY + fraction * deltaY);
}
function haversineDistanceMetres(first: Coordinate, second: Coordinate): number {
  const latitudeDelta = toRadians(second.latitude - first.latitude);
  const longitudeDelta = toRadians(second.longitude - first.longitude);
  const a = Math.sin(latitudeDelta / 2) ** 2 + Math.cos(toRadians(first.latitude)) *
    Math.cos(toRadians(second.latitude)) * Math.sin(longitudeDelta / 2) ** 2;
  return 6_371_008.8 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}
function compareOsmEvidence(first: OsmEvidence, second: OsmEvidence): number {
  if (first.type !== second.type) return first.type < second.type ? -1 : 1;
  return BigInt(first.id) < BigInt(second.id) ? -1 : BigInt(first.id) > BigInt(second.id) ? 1 : 0;
}
function parseOsmId(value: unknown): string | null {
  if (typeof value === "number" && Number.isSafeInteger(value) && value > 0) return String(value);
  return typeof value === "string" && /^[1-9][0-9]*$/.test(value) ? value : null;
}
function isFiniteCoordinate(value: unknown, minimum: number, maximum: number): value is number {
  return typeof value === "number" && Number.isFinite(value) && value >= minimum && value <= maximum;
}
function isFiniteNonNegativeNumber(value: unknown): value is number { return typeof value === "number" && Number.isFinite(value) && value >= 0; }
function declaredLengthExceedsLimit(contentLength: string | null, maximumBytes: number): boolean {
  if (contentLength === null) return false;
  if (!/^[0-9]+$/.test(contentLength.trim())) return true;
  const value = Number(contentLength);
  return !Number.isSafeInteger(value) || value > maximumBytes;
}
async function readAbortableChunk(reader: ReadableStreamDefaultReader<Uint8Array>, signal: AbortSignal | undefined): Promise<ReadableStreamReadResult<Uint8Array>> {
  if (signal === undefined) return reader.read();
  if (signal.aborted) throw new DOMException("Aborted", "AbortError");
  return await new Promise((resolve, reject) => {
    const onAbort = () => reject(new DOMException("Aborted", "AbortError"));
    signal.addEventListener("abort", onAbort, { once: true });
    void reader.read().then(resolve, reject).finally(() => signal.removeEventListener("abort", onAbort));
  });
}
function normalizeCoordinate(value: number): number { return Object.is(value, -0) ? 0 : value; }
function clampInteger(value: number, minimum: number, maximum: number): number { return Math.max(minimum, Math.min(maximum, Math.round(value))); }
function round(value: number, decimalPlaces: number): number { const scale = 10 ** decimalPlaces; return Math.round(value * scale) / scale; }
function toRadians(degrees: number): number { return degrees * Math.PI / 180; }
function toDegrees(radians: number): number { return radians * 180 / Math.PI; }

class ExactJsonCursor {
  #offset = 0;
  constructor(private readonly source: string) {}
  readExactNumericObject(): Record<string, number> {
    this.skipWhitespace(); this.expect("{"); this.skipWhitespace();
    const result: Record<string, number> = {}; const seen = new Set<string>();
    if (this.peek() === "}") throw new InvalidSiteFactorIntelligenceRequest();
    while (true) {
      this.skipWhitespace(); const key = this.readString();
      if (seen.has(key)) throw new InvalidSiteFactorIntelligenceRequest();
      seen.add(key); this.skipWhitespace(); this.expect(":"); this.skipWhitespace();
      result[key] = this.readNumber(); this.skipWhitespace();
      if (this.peek() === "}") { this.#offset += 1; return result; }
      this.expect(",");
    }
  }
  requireEnd(): void { this.skipWhitespace(); if (this.#offset !== this.source.length) throw new InvalidSiteFactorIntelligenceRequest(); }
  private readString(): string {
    const start = this.#offset; this.expect('"');
    while (this.#offset < this.source.length) {
      const character = this.source[this.#offset];
      if (character === '"') { this.#offset += 1; try { return JSON.parse(this.source.slice(start, this.#offset)) as string; } catch (_) { throw new InvalidSiteFactorIntelligenceRequest(); } }
      if (character.charCodeAt(0) < 0x20) throw new InvalidSiteFactorIntelligenceRequest();
      if (character === "\\") {
        this.#offset += 1; const escape = this.source[this.#offset];
        if (escape === "u") { if (!/^[0-9a-fA-F]{4}$/.test(this.source.slice(this.#offset + 1, this.#offset + 5))) throw new InvalidSiteFactorIntelligenceRequest(); this.#offset += 5; continue; }
        if (escape === undefined || !'"\\/bfnrt'.includes(escape)) throw new InvalidSiteFactorIntelligenceRequest();
      }
      this.#offset += 1;
    }
    throw new InvalidSiteFactorIntelligenceRequest();
  }
  private readNumber(): number {
    const start = this.#offset; if (this.peek() === "-") this.#offset += 1;
    if (this.peek() === "0") this.#offset += 1; else this.readDigits();
    if (this.peek() === ".") { this.#offset += 1; this.readDigits(); }
    if (this.peek() === "e" || this.peek() === "E") { this.#offset += 1; if (this.peek() === "+" || this.peek() === "-") this.#offset += 1; this.readDigits(); }
    const value = Number(this.source.slice(start, this.#offset));
    if (!Number.isFinite(value)) throw new InvalidSiteFactorIntelligenceRequest();
    return value;
  }
  private readDigits(): void { const start = this.#offset; while (this.#offset < this.source.length && /[0-9]/.test(this.source[this.#offset])) this.#offset += 1; if (start === this.#offset) throw new InvalidSiteFactorIntelligenceRequest(); }
  private skipWhitespace(): void { while (this.#offset < this.source.length && " \t\n\r".includes(this.source[this.#offset])) this.#offset += 1; }
  private expect(expected: string): void { if (this.peek() !== expected) throw new InvalidSiteFactorIntelligenceRequest(); this.#offset += 1; }
  private peek(): string | undefined { return this.source[this.#offset]; }
}
