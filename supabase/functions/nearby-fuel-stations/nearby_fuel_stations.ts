export const supportedAnalysisRadiiKm = [3, 5, 10] as const;
export const overpassEndpoint = "https://overpass-api.de/api/interpreter";
// Fixed fallback for temporary main-instance queues or rate limits. It is
// invoked only by the Edge Function after the primary endpoint fails.
export const fallbackOverpassEndpoint =
  "https://overpass.private.coffee/api/interpreter";
// A small fuel-only query normally completes quickly. Keep the combined
// primary and fallback wait within the former 30-second single-server bound.
export const overpassTimeoutMs = 18_000;
export const fallbackOverpassTimeoutMs = 12_000;
export const maximumRequestBodyBytes = 4_096;
export const maximumOverpassResponseBytes = 1_024 * 1_024;
export const maximumUpstreamElementCount = 500;
export const maximumReturnedStationCount = 100;
export const openStreetMapAttribution = "© OpenStreetMap contributors";
export const openStreetMapAttributionUrl =
  "https://www.openstreetmap.org/copyright";

export type OsmType = "node" | "way" | "relation";

export interface NearbyFuelStationsRequest {
  latitude: number;
  longitude: number;
  analysisRadiusKm: 3 | 5 | 10;
}

export interface NearbyFuelStation {
  osmType: OsmType;
  osmId: string;
  name: string | null;
  brand: string | null;
  operator: string | null;
  latitude: number;
  longitude: number;
  distanceKm: number;
}

export interface NearbyFuelStationsResult {
  source: "openstreetmap";
  attribution: typeof openStreetMapAttribution;
  attributionUrl: typeof openStreetMapAttributionUrl;
  fetchedAt: string;
  analysisRadiusKm: 3 | 5 | 10;
  latitude: number;
  longitude: number;
  stationCount: number;
  nearestDistanceKm: number | null;
  stations: NearbyFuelStation[];
}

export class InvalidNearbyFuelStationsRequest extends Error {
  constructor(message = "Invalid nearby fuel-stations request.") {
    super(message);
    this.name = "InvalidNearbyFuelStationsRequest";
  }
}

export class UpstreamFuelStationsFailure extends Error {
  readonly retryable: boolean;

  constructor(
    message = "OpenStreetMap fuel-station data is unavailable.",
    { retryable = true }: { retryable?: boolean } = {},
  ) {
    super(message);
    this.name = "UpstreamFuelStationsFailure";
    this.retryable = retryable;
  }
}

export function parseNearbyFuelStationsRequest(
  value: unknown,
): NearbyFuelStationsRequest {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new InvalidNearbyFuelStationsRequest();
  }

  const record = value as Record<string, unknown>;
  const keys = Object.keys(record).sort();
  const expectedKeys = ["analysis_radius_km", "latitude", "longitude"];
  if (
    keys.length !== expectedKeys.length ||
    keys.some((key, index) => key !== expectedKeys[index])
  ) {
    throw new InvalidNearbyFuelStationsRequest();
  }

  const latitude = record.latitude;
  const longitude = record.longitude;
  const radius = record.analysis_radius_km;
  if (
    typeof latitude !== "number" ||
    typeof longitude !== "number" ||
    typeof radius !== "number"
  ) {
    throw new InvalidNearbyFuelStationsRequest();
  }

  return validateNearbyFuelStationsRequest({
    latitude,
    longitude,
    analysisRadiusKm: radius,
  });
}

export function parseNearbyFuelStationsRequestJson(
  rawJson: string,
): NearbyFuelStationsRequest {
  const cursor = new ExactNearbyFuelStationsJsonCursor(rawJson);
  const record = cursor.readExactObject();
  cursor.requireEnd();
  return parseNearbyFuelStationsRequest(record);
}

export async function parseBoundedNearbyFuelStationsRequestBody(
  body: ReadableStream<Uint8Array> | null,
  contentLength: string | null,
): Promise<NearbyFuelStationsRequest> {
  const rawJson = await readBoundedUtf8Body(
    body,
    contentLength,
    maximumRequestBodyBytes,
    () => new InvalidNearbyFuelStationsRequest(),
  );
  return parseNearbyFuelStationsRequestJson(rawJson);
}

export async function parseBoundedNearbyFuelStationsRequest(
  request: Request,
): Promise<NearbyFuelStationsRequest> {
  return parseBoundedNearbyFuelStationsRequestBody(
    request.body,
    request.headers.get("content-length"),
  );
}

export function validateNearbyFuelStationsRequest(value: {
  latitude: number;
  longitude: number;
  analysisRadiusKm: number;
}): NearbyFuelStationsRequest {
  if (
    !Number.isFinite(value.latitude) ||
    value.latitude < -90 ||
    value.latitude > 90 ||
    !Number.isFinite(value.longitude) ||
    value.longitude < -180 ||
    value.longitude > 180 ||
    !Number.isFinite(value.analysisRadiusKm) ||
    !supportedAnalysisRadiiKm.includes(value.analysisRadiusKm as 3 | 5 | 10)
  ) {
    throw new InvalidNearbyFuelStationsRequest();
  }

  return {
    latitude: normalizeCoordinate(value.latitude),
    longitude: normalizeCoordinate(value.longitude),
    analysisRadiusKm: value.analysisRadiusKm as 3 | 5 | 10,
  };
}

export function buildFixedOverpassQuery(
  request: NearbyFuelStationsRequest,
): string {
  const radiusMetres = request.analysisRadiusKm * 1000;

  // Values are validated finite numbers; this fixed query never receives
  // client-supplied Overpass QL, tags, or upstream endpoint information.
  return `[out:json][timeout:25];\n(\n  nwr(around:${radiusMetres},${request.latitude},${request.longitude})["amenity"="fuel"];\n);\nout center tags;`;
}

export function parseOverpassFuelStations(
  payload: unknown,
  request: NearbyFuelStationsRequest,
  maximumReturnedCount = maximumReturnedStationCount,
): NearbyFuelStation[] {
  if (
    payload === null ||
    typeof payload !== "object" ||
    Array.isArray(payload) ||
    !Array.isArray((payload as Record<string, unknown>).elements)
  ) {
    throw new UpstreamFuelStationsFailure();
  }

  const elements = (payload as { elements: unknown[] }).elements;
  if (elements.length > maximumUpstreamElementCount) {
    throw new UpstreamFuelStationsFailure();
  }
  if (!Number.isInteger(maximumReturnedCount) || maximumReturnedCount < 1) {
    throw new RangeError("maximumReturnedCount must be a positive integer.");
  }

  const deduplicated = new Map<string, NearbyFuelStation>();
  for (const element of elements) {
    const station = parseOverpassElement(element, request);
    if (station !== null) {
      deduplicated.set(`${station.osmType}:${station.osmId}`, station);
    }
  }

  return [...deduplicated.values()]
    .sort(compareStations)
    .slice(0, maximumReturnedCount);
}

export function makeNearbyFuelStationsResult(
  request: NearbyFuelStationsRequest,
  stations: NearbyFuelStation[],
  fetchedAt: Date,
): NearbyFuelStationsResult {
  const orderedStations = [...stations].sort(compareStations);
  return {
    source: "openstreetmap",
    attribution: openStreetMapAttribution,
    attributionUrl: openStreetMapAttributionUrl,
    fetchedAt: fetchedAt.toISOString(),
    analysisRadiusKm: request.analysisRadiusKm,
    latitude: request.latitude,
    longitude: request.longitude,
    stationCount: orderedStations.length,
    nearestDistanceKm: orderedStations[0]?.distanceKm ?? null,
    stations: orderedStations,
  };
}

export function toNearbyFuelStationsPublicResponse(
  result: NearbyFuelStationsResult,
): Record<string, unknown> {
  return {
    source: result.source,
    attribution: result.attribution,
    attribution_url: result.attributionUrl,
    fetched_at: result.fetchedAt,
    analysis_radius_km: result.analysisRadiusKm,
    latitude: result.latitude,
    longitude: result.longitude,
    station_count: result.stationCount,
    nearest_distance_km: result.nearestDistanceKm,
    stations: result.stations.map((station) => ({
      osm_type: station.osmType,
      osm_id: station.osmId,
      name: station.name,
      brand: station.brand,
      operator: station.operator,
      latitude: station.latitude,
      longitude: station.longitude,
      distance_km: station.distanceKm,
    })),
  };
}

/**
 * Treats a cache RPC value as untrusted input. The database constraint is the
 * primary guard; this independent check makes a malformed or stale cache row
 * a safe miss instead of an application response.
 */
export function parseCachedNearbyFuelStationsResult(
  value: unknown,
  request: NearbyFuelStationsRequest,
  databaseFetchedAt: unknown,
): NearbyFuelStationsResult {
  if (
    value === null ||
    typeof value !== "object" ||
    Array.isArray(value) ||
    typeof databaseFetchedAt !== "string"
  ) {
    throw new Error("cache result is invalid");
  }

  const result = value as Record<string, unknown>;
  const expectedKeys = [
    "analysis_radius_km",
    "attribution",
    "attribution_url",
    "fetched_at",
    "latitude",
    "longitude",
    "nearest_distance_km",
    "source",
    "station_count",
    "stations",
  ];
  const actualKeys = Object.keys(result).sort();
  if (
    actualKeys.length !== expectedKeys.length ||
    actualKeys.some((key, index) => key !== expectedKeys[index]) ||
    result.source !== "openstreetmap" ||
    result.attribution !== openStreetMapAttribution ||
    result.attribution_url !== openStreetMapAttributionUrl ||
    typeof result.fetched_at !== "string" ||
    result.analysis_radius_km !== request.analysisRadiusKm ||
    !sameCoordinate(result.latitude, request.latitude) ||
    !sameCoordinate(result.longitude, request.longitude) ||
    !Array.isArray(result.stations) ||
    typeof result.station_count !== "number" ||
    !Number.isInteger(result.station_count) ||
    result.station_count < 0 ||
    result.station_count > maximumReturnedStationCount ||
    result.station_count !== result.stations.length
  ) {
    throw new Error("cache result is invalid");
  }

  const stations = result.stations.map(parseCachedStation);
  for (let index = 1; index < stations.length; index += 1) {
    if (compareStations(stations[index - 1], stations[index]) > 0) {
      throw new Error("cache result is invalid");
    }
  }

  const nearestDistanceKm = result.nearest_distance_km;
  if (
    (stations.length === 0 && nearestDistanceKm !== null) ||
    (stations.length > 0 &&
      (!isFiniteNonNegativeNumber(nearestDistanceKm) ||
        nearestDistanceKm !== stations[0].distanceKm))
  ) {
    throw new Error("cache result is invalid");
  }

  return {
    source: "openstreetmap",
    attribution: openStreetMapAttribution,
    attributionUrl: openStreetMapAttributionUrl,
    fetchedAt: databaseFetchedAt,
    analysisRadiusKm: request.analysisRadiusKm,
    latitude: result.latitude,
    longitude: result.longitude,
    stationCount: result.station_count,
    nearestDistanceKm: nearestDistanceKm as number | null,
    stations,
  };
}

export function haversineDistanceKm(
  fromLatitude: number,
  fromLongitude: number,
  toLatitude: number,
  toLongitude: number,
): number {
  const earthRadiusKm = 6371.0088;
  const toRadians = (degrees: number) => (degrees * Math.PI) / 180;
  const latitudeDelta = toRadians(toLatitude - fromLatitude);
  const longitudeDelta = toRadians(toLongitude - fromLongitude);
  const a =
    Math.sin(latitudeDelta / 2) ** 2 +
    Math.cos(toRadians(fromLatitude)) *
      Math.cos(toRadians(toLatitude)) *
      Math.sin(longitudeDelta / 2) ** 2;
  return earthRadiusKm * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function parseOverpassElement(
  value: unknown,
  request: NearbyFuelStationsRequest,
): NearbyFuelStation | null {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    return null;
  }

  const element = value as Record<string, unknown>;
  const osmType = element.type;
  const osmId = parseOsmId(element.id);
  if (
    (osmType !== "node" && osmType !== "way" && osmType !== "relation") ||
    osmId === null
  ) {
    return null;
  }

  const coordinateSource =
    osmType === "node" ? element : element.center;
  const coordinates = parseCoordinates(coordinateSource);
  if (coordinates === null) return null;

  const tags =
    element.tags !== null && typeof element.tags === "object" &&
      !Array.isArray(element.tags)
      ? element.tags as Record<string, unknown>
      : {};
  return {
    osmType,
    osmId,
    name: optionalTag(tags.name),
    brand: optionalTag(tags.brand),
    operator: optionalTag(tags.operator),
    latitude: coordinates.latitude,
    longitude: coordinates.longitude,
    distanceKm: haversineDistanceKm(
      request.latitude,
      request.longitude,
      coordinates.latitude,
      coordinates.longitude,
    ),
  };
}

function parseCoordinates(value: unknown): {
  latitude: number;
  longitude: number;
} | null {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    return null;
  }
  const record = value as Record<string, unknown>;
  if (
    typeof record.lat !== "number" ||
    typeof record.lon !== "number" ||
    !Number.isFinite(record.lat) ||
    !Number.isFinite(record.lon) ||
    record.lat < -90 ||
    record.lat > 90 ||
    record.lon < -180 ||
    record.lon > 180
  ) {
    return null;
  }
  return { latitude: record.lat, longitude: record.lon };
}

function parseCachedStation(value: unknown): NearbyFuelStation {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("cache result is invalid");
  }
  const station = value as Record<string, unknown>;
  const expectedKeys = [
    "brand",
    "distance_km",
    "latitude",
    "longitude",
    "name",
    "operator",
    "osm_id",
    "osm_type",
  ];
  const actualKeys = Object.keys(station).sort();
  if (
    actualKeys.length !== expectedKeys.length ||
    actualKeys.some((key, index) => key !== expectedKeys[index]) ||
    (station.osm_type !== "node" &&
      station.osm_type !== "way" &&
      station.osm_type !== "relation") ||
    typeof station.osm_id !== "string" ||
    !/^[1-9][0-9]*$/.test(station.osm_id) ||
    !isNullableString(station.name) ||
    !isNullableString(station.brand) ||
    !isNullableString(station.operator) ||
    !isFiniteCoordinate(station.latitude, -90, 90) ||
    !isFiniteCoordinate(station.longitude, -180, 180) ||
    !isFiniteNonNegativeNumber(station.distance_km)
  ) {
    throw new Error("cache result is invalid");
  }
  return {
    osmType: station.osm_type,
    osmId: station.osm_id,
    name: station.name,
    brand: station.brand,
    operator: station.operator,
    latitude: station.latitude,
    longitude: station.longitude,
    distanceKm: station.distance_km,
  };
}

function isNullableString(value: unknown): value is string | null {
  return value === null || typeof value === "string";
}

function isFiniteCoordinate(
  value: unknown,
  minimum: number,
  maximum: number,
): value is number {
  return typeof value === "number" && Number.isFinite(value) &&
    value >= minimum && value <= maximum;
}

function isFiniteNonNegativeNumber(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value) && value >= 0;
}

function sameCoordinate(value: unknown, expected: number): value is number {
  return typeof value === "number" && Number.isFinite(value) &&
    (Object.is(value, expected) || (value === 0 && expected === 0));
}

function parseOsmId(value: unknown): string | null {
  if (
    typeof value === "number" &&
    Number.isSafeInteger(value) &&
    value > 0
  ) {
    return String(value);
  }
  if (typeof value === "string" && /^[1-9][0-9]*$/.test(value)) {
    return value;
  }
  return null;
}

function optionalTag(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed === "" ? null : trimmed;
}

export function normalizeCoordinate(value: number): number {
  return Object.is(value, -0) ? 0 : value;
}

export function parseBearerToken(value: string | null): string | null {
  if (value === null) return null;
  const match = /^Bearer\s+(.+)$/i.exec(value);
  return match?.[1]?.trim() || null;
}

export async function readBoundedUtf8Body(
  body: ReadableStream<Uint8Array> | null,
  contentLength: string | null,
  maximumBytes: number,
  createError: () => Error,
  signal?: AbortSignal,
  onLimitExceeded?: () => void,
): Promise<string> {
  if (body === null || !Number.isSafeInteger(maximumBytes) || maximumBytes < 1) {
    throw createError();
  }
  if (declaredLengthExceedsLimit(contentLength, maximumBytes)) {
    await cancelBody(body);
    notifyLimitExceeded(onLimitExceeded);
    throw createError();
  }

  const reader = body.getReader();
  const cancelReader = createIdempotentReaderCancellation(reader);
  const chunks: Uint8Array[] = [];
  let totalBytes = 0;
  try {
    while (true) {
      const next = await readAbortableChunk(reader, signal, cancelReader);
      if (next.done) break;
      totalBytes += next.value.byteLength;
      if (totalBytes > maximumBytes) {
        notifyLimitExceeded(onLimitExceeded);
        throw createError();
      }
      chunks.push(next.value);
    }
  } catch (_) {
    await cancelReader();
    throw createError();
  } finally {
    reader.releaseLock();
  }

  const bytes = new Uint8Array(totalBytes);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  try {
    return new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch (_) {
    throw createError();
  }
}

async function cancelBody(body: ReadableStream<Uint8Array>): Promise<void> {
  await body.cancel().catch(() => undefined);
}

function createIdempotentReaderCancellation(
  reader: ReadableStreamDefaultReader<Uint8Array>,
): () => Promise<void> {
  let cancellationStarted = false;
  let cancellation: Promise<void> | undefined;

  return () => {
    if (cancellationStarted) return cancellation!;
    cancellationStarted = true;
    try {
      cancellation = Promise.resolve(reader.cancel()).then(
        () => undefined,
        () => undefined,
      );
    } catch (_) {
      cancellation = Promise.resolve();
    }
    return cancellation;
  };
}

function notifyLimitExceeded(callback: (() => void) | undefined): void {
  try {
    callback?.();
  } catch (_) {
    // A best-effort abort must not mask the neutral size-limit error.
  }
}

function declaredLengthExceedsLimit(
  contentLength: string | null,
  maximumBytes: number,
): boolean {
  if (contentLength === null) return false;
  const value = contentLength.trim();
  if (!/^[0-9]+$/.test(value)) return true;
  const length = Number(value);
  return !Number.isSafeInteger(length) || length > maximumBytes;
}

async function readAbortableChunk(
  reader: ReadableStreamDefaultReader<Uint8Array>,
  signal: AbortSignal | undefined,
  cancelReader: () => Promise<void>,
): Promise<ReadableStreamReadResult<Uint8Array>> {
  if (signal === undefined) return reader.read();
  if (signal.aborted) {
    void cancelReader();
    throw new DOMException("Aborted", "AbortError");
  }

  return await new Promise((resolve, reject) => {
    const onAbort = () => {
      void cancelReader();
      reject(new DOMException("Aborted", "AbortError"));
    };
    signal.addEventListener("abort", onAbort, { once: true });
    void reader.read().then(
      (value) => resolve(value),
      (error) => reject(error),
    ).finally(() => signal.removeEventListener("abort", onAbort));
  });
}

class ExactNearbyFuelStationsJsonCursor {
  #offset = 0;
  private readonly source: string;

  constructor(source: string) {
    this.source = source;
  }

  readExactObject(): Record<string, number> {
    this.skipWhitespace();
    this.expect("{");
    this.skipWhitespace();
    const values: Record<string, number> = {};
    const seen = new Set<string>();
    if (this.peek() === "}") throw new InvalidNearbyFuelStationsRequest();

    while (true) {
      this.skipWhitespace();
      const key = this.readString();
      if (seen.has(key)) throw new InvalidNearbyFuelStationsRequest();
      seen.add(key);
      this.skipWhitespace();
      this.expect(":");
      this.skipWhitespace();
      values[key] = this.readNumber();
      this.skipWhitespace();
      if (this.peek() === "}") {
        this.#offset += 1;
        return values;
      }
      this.expect(",");
    }
  }

  requireEnd(): void {
    this.skipWhitespace();
    if (this.#offset !== this.source.length) {
      throw new InvalidNearbyFuelStationsRequest();
    }
  }

  private readString(): string {
    const start = this.#offset;
    this.expect('"');
    while (this.#offset < this.source.length) {
      const character = this.source[this.#offset];
      if (character === '"') {
        this.#offset += 1;
        try {
          return JSON.parse(this.source.slice(start, this.#offset)) as string;
        } catch (_) {
          throw new InvalidNearbyFuelStationsRequest();
        }
      }
      if (character.charCodeAt(0) < 0x20) {
        throw new InvalidNearbyFuelStationsRequest();
      }
      if (character === "\\") {
        this.#offset += 1;
        const escape = this.source[this.#offset];
        if (escape === "u") {
          const hex = this.source.slice(this.#offset + 1, this.#offset + 5);
          if (!/^[0-9a-fA-F]{4}$/.test(hex)) {
            throw new InvalidNearbyFuelStationsRequest();
          }
          this.#offset += 5;
          continue;
        }
        if (escape === undefined || !'"\\/bfnrt'.includes(escape)) {
          throw new InvalidNearbyFuelStationsRequest();
        }
      }
      this.#offset += 1;
    }
    throw new InvalidNearbyFuelStationsRequest();
  }

  private readNumber(): number {
    const start = this.#offset;
    if (this.peek() === "-") this.#offset += 1;
    if (this.peek() === "0") {
      this.#offset += 1;
    } else {
      this.readDigits();
    }
    if (this.peek() === ".") {
      this.#offset += 1;
      this.readDigits();
    }
    if (this.peek() === "e" || this.peek() === "E") {
      this.#offset += 1;
      if (this.peek() === "+" || this.peek() === "-") this.#offset += 1;
      this.readDigits();
    }
    const value = Number(this.source.slice(start, this.#offset));
    if (!Number.isFinite(value)) throw new InvalidNearbyFuelStationsRequest();
    return value;
  }

  private readDigits(): void {
    const start = this.#offset;
    while (this.#offset < this.source.length && /[0-9]/.test(this.source[this.#offset])) {
      this.#offset += 1;
    }
    if (start === this.#offset) throw new InvalidNearbyFuelStationsRequest();
  }

  private skipWhitespace(): void {
    while (this.#offset < this.source.length && " \t\n\r".includes(this.source[this.#offset])) {
      this.#offset += 1;
    }
  }

  private expect(expected: string): void {
    if (this.peek() !== expected) throw new InvalidNearbyFuelStationsRequest();
    this.#offset += 1;
  }

  private peek(): string | undefined {
    return this.source[this.#offset];
  }
}

function compareStations(
  first: NearbyFuelStation,
  second: NearbyFuelStation,
): number {
  if (first.distanceKm !== second.distanceKm) {
    return first.distanceKm - second.distanceKm;
  }
  if (first.osmType !== second.osmType) {
    return first.osmType < second.osmType ? -1 : 1;
  }
  if (first.osmId === second.osmId) return 0;
  return first.osmId < second.osmId ? -1 : 1;
}
