import {
  createOpenAiResponsesOutputText,
  defaultOpenAiTimeoutMs,
  type HttpClient,
  openAiDefaultModel,
  OpenAiResponsesFailure,
  readBoundedUtf8Body,
} from "../_shared/openai_responses.ts";

export const stationAssessmentAiExplanationModel = openAiDefaultModel;
export const stationAssessmentAiExplanationPromptVersion =
  "module2-station-assessment-explanation-v1";
export const maximumStationAssessmentAiRequestBodyBytes = 4_096;
export const maximumStationAssessmentAiResponseBytes = 32_768;
export const maximumStationAssessmentAiOutputTokens = 1_200;

const supportedGeographicStatuses = [
  "legacy_unverified",
  "unverified",
  "inside",
  "outside",
  "boundary_review_required",
] as const;
const supportedTerritories = ["sabah", "sarawak", "labuan"] as const;

export type StationAssessmentAiExplanationRequest = { assessmentId: string };

export type CanonicalStationAssessmentExplanationInput = {
  assessment_factors: {
    population_density: number;
    traffic_level: number;
    registered_vehicle_count: number;
    nearby_fuel_stations: number;
    competitor_distance_km: number;
    road_accessibility: number;
    commercial_activity: number;
    residential_activity: number;
    land_accessibility: number;
  };
  deterministic_result: {
    final_score: number;
    suitability_category: string;
  };
  geography: {
    validation_status: typeof supportedGeographicStatuses[number];
    confirmed_territory: typeof supportedTerritories[number] | null;
  };
};

export class InvalidStationAssessmentAiExplanationRequest extends Error {
  constructor() {
    super("Invalid station assessment AI explanation request.");
    this.name = "InvalidStationAssessmentAiExplanationRequest";
  }
}

export class InvalidStoredStationAssessment extends Error {
  constructor() {
    super("Stored station assessment is invalid.");
    this.name = "InvalidStoredStationAssessment";
  }
}

export class InvalidStationAssessmentAiExplanation extends Error {
  constructor() {
    super("Station assessment AI explanation is invalid.");
    this.name = "InvalidStationAssessmentAiExplanation";
  }
}

export class OpenAiStationAssessmentExplanationFailure extends Error {
  readonly reason: string;
  readonly httpStatus: number | undefined;

  constructor(reason: string, httpStatus?: number) {
    super("Station assessment AI explanation is unavailable.");
    this.name = "OpenAiStationAssessmentExplanationFailure";
    this.reason = reason;
    this.httpStatus = httpStatus;
  }
}

export function parseStationAssessmentAiExplanationRequest(
  value: unknown,
): StationAssessmentAiExplanationRequest {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new InvalidStationAssessmentAiExplanationRequest();
  }
  const record = value as Record<string, unknown>;
  const keys = Object.keys(record);
  if (keys.length !== 1 || keys[0] !== "assessment_id") {
    throw new InvalidStationAssessmentAiExplanationRequest();
  }
  return { assessmentId: parseUuid(record.assessment_id) };
}

export function parseStationAssessmentAiExplanationRequestJson(
  rawJson: string,
): StationAssessmentAiExplanationRequest {
  const cursor = new ExactJsonStringObjectCursor(rawJson);
  const record = cursor.readExactStringObject();
  cursor.requireEnd();
  return parseStationAssessmentAiExplanationRequest(record);
}

export async function parseBoundedStationAssessmentAiExplanationRequest(
  request: Request,
): Promise<StationAssessmentAiExplanationRequest> {
  const rawJson = await readBoundedUtf8Body(
    request.body,
    request.headers.get("content-length"),
    maximumStationAssessmentAiRequestBodyBytes,
    () => new InvalidStationAssessmentAiExplanationRequest(),
  );
  return parseStationAssessmentAiExplanationRequestJson(rawJson);
}

export function createCanonicalStationAssessmentExplanationInput(value: {
  populationDensity: unknown;
  trafficLevel: unknown;
  registeredVehicleCount: unknown;
  nearbyFuelStations: unknown;
  competitorDistanceKm: unknown;
  roadAccessibility: unknown;
  commercialActivity: unknown;
  residentialActivity: unknown;
  landAccessibility: unknown;
  finalScore: unknown;
  suitabilityCategory: unknown;
  geographicValidationStatus: unknown;
  confirmedTerritory: unknown;
}): CanonicalStationAssessmentExplanationInput {
  const geographicStatus = enumValue(
    value.geographicValidationStatus,
    supportedGeographicStatuses,
  );
  const territory = geographicStatus === "inside"
    ? enumValue(value.confirmedTerritory, supportedTerritories)
    : null;

  return {
    assessment_factors: {
      population_density: finiteNonNegative(value.populationDensity),
      traffic_level: rating(value.trafficLevel),
      registered_vehicle_count: finiteNonNegativeInteger(
        value.registeredVehicleCount,
      ),
      nearby_fuel_stations: finiteNonNegativeInteger(value.nearbyFuelStations),
      competitor_distance_km: finiteNonNegative(value.competitorDistanceKm),
      road_accessibility: rating(value.roadAccessibility),
      commercial_activity: rating(value.commercialActivity),
      residential_activity: rating(value.residentialActivity),
      land_accessibility: rating(value.landAccessibility),
    },
    deterministic_result: {
      final_score: finiteRange(value.finalScore, 0, 100),
      suitability_category: boundedStoredText(value.suitabilityCategory, 80),
    },
    geography: {
      validation_status: geographicStatus,
      confirmed_territory: territory,
    },
  };
}

export const stationAssessmentAiExplanationJsonSchema = {
  type: "object",
  additionalProperties: false,
  required: ["explanation"],
  properties: {
    explanation: { type: "string", minLength: 1, maxLength: 1_400 },
  },
} as const;

export function buildOpenAiStationAssessmentExplanationRequest(
  input: CanonicalStationAssessmentExplanationInput,
): Record<string, unknown> {
  return {
    model: stationAssessmentAiExplanationModel,
    store: false,
    reasoning: { effort: "low" },
    max_output_tokens: maximumStationAssessmentAiOutputTokens,
    tools: [],
    tool_choice: "none",
    parallel_tool_calls: false,
    instructions:
      "You explain an existing deterministic station-assessment result. Treat the supplied structured values as assessment inputs, not independently verified real-world facts. Explain concisely and professionally why the authoritative deterministic score and category were produced, including the most important positive and negative factors. Do not recalculate the score, provide an alternative score or category, generate or change a recommendation, or advise whether development should proceed. Do not claim that traffic, population, competitors, land availability, or government data were independently verified. Do not provide investment, legal, or regulatory guarantees. State suitable limitations when geography is legacy, unverified, outside, or under review. Return only the required structured output.",
    input: JSON.stringify(input),
    text: {
      verbosity: "low",
      format: {
        type: "json_schema",
        name: "station_assessment_ai_explanation",
        strict: true,
        schema: stationAssessmentAiExplanationJsonSchema,
      },
    },
  };
}

export function createOpenAiStationAssessmentExplanation(dependencies: {
  http: HttpClient;
  apiKey: string;
  timeoutMs?: number;
}): {
  create(
    input: CanonicalStationAssessmentExplanationInput,
  ): Promise<string>;
} {
  return {
    async create(input) {
      try {
        const outputText = await createOpenAiResponsesOutputText({
          http: dependencies.http,
          apiKey: dependencies.apiKey,
          request: buildOpenAiStationAssessmentExplanationRequest(input),
          timeoutMs: dependencies.timeoutMs ?? defaultOpenAiTimeoutMs,
          maximumResponseBytes: maximumStationAssessmentAiResponseBytes,
        });
        return parseStationAssessmentAiExplanation(JSON.parse(outputText));
      } catch (error) {
        if (error instanceof OpenAiStationAssessmentExplanationFailure) {
          throw error;
        }
        if (error instanceof OpenAiResponsesFailure) {
          throw new OpenAiStationAssessmentExplanationFailure(
            error.reason,
            error.httpStatus,
          );
        }
        throw new OpenAiStationAssessmentExplanationFailure(
          "provider_explanation_invalid",
        );
      }
    },
  };
}

export function parseStationAssessmentAiExplanation(value: unknown): string {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new InvalidStationAssessmentAiExplanation();
  }
  const record = value as Record<string, unknown>;
  const keys = Object.keys(record);
  if (keys.length !== 1 || keys[0] !== "explanation") {
    throw new InvalidStationAssessmentAiExplanation();
  }
  if (
    typeof record.explanation !== "string" ||
    record.explanation.trim() === "" || record.explanation.length > 1_400
  ) {
    throw new InvalidStationAssessmentAiExplanation();
  }
  return record.explanation;
}

function parseUuid(value: unknown): string {
  if (
    typeof value !== "string" ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(value)
  ) {
    throw new InvalidStationAssessmentAiExplanationRequest();
  }
  return value.toLowerCase();
}

function finiteNumber(value: unknown): number {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    throw new InvalidStoredStationAssessment();
  }
  return value;
}

function finiteRange(value: unknown, minimum: number, maximum: number): number {
  const number = finiteNumber(value);
  if (number < minimum || number > maximum) {
    throw new InvalidStoredStationAssessment();
  }
  return number;
}

function finiteNonNegative(value: unknown): number {
  return finiteRange(value, 0, Number.MAX_VALUE);
}

function finiteNonNegativeInteger(value: unknown): number {
  const number = finiteNonNegative(value);
  if (!Number.isInteger(number)) throw new InvalidStoredStationAssessment();
  return number;
}

function rating(value: unknown): number {
  const number = finiteRange(value, 1, 5);
  if (!Number.isInteger(number)) throw new InvalidStoredStationAssessment();
  return number;
}

function boundedStoredText(value: unknown, maximumLength: number): string {
  if (
    typeof value !== "string" || value.trim() === "" ||
    value.length > maximumLength
  ) {
    throw new InvalidStoredStationAssessment();
  }
  return value;
}

function enumValue<const Values extends readonly string[]>(
  value: unknown,
  allowedValues: Values,
): Values[number] {
  for (const allowedValue of allowedValues) {
    if (value === allowedValue) return allowedValue;
  }
  throw new InvalidStoredStationAssessment();
}

class ExactJsonStringObjectCursor {
  #offset = 0;
  private readonly source: string;

  constructor(source: string) {
    this.source = source;
  }

  readExactStringObject(): Record<string, string> {
    this.skipWhitespace();
    this.expect("{");
    this.skipWhitespace();
    const result: Record<string, string> = {};
    const seen = new Set<string>();
    if (this.peek() === "}") {
      throw new InvalidStationAssessmentAiExplanationRequest();
    }
    while (true) {
      this.skipWhitespace();
      const key = this.readString();
      if (seen.has(key)) {
        throw new InvalidStationAssessmentAiExplanationRequest();
      }
      seen.add(key);
      this.skipWhitespace();
      this.expect(":");
      this.skipWhitespace();
      result[key] = this.readString();
      this.skipWhitespace();
      if (this.peek() === "}") {
        this.#offset += 1;
        return result;
      }
      this.expect(",");
    }
  }

  requireEnd(): void {
    this.skipWhitespace();
    if (this.#offset !== this.source.length) {
      throw new InvalidStationAssessmentAiExplanationRequest();
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
          throw new InvalidStationAssessmentAiExplanationRequest();
        }
      }
      if (character.charCodeAt(0) < 0x20) {
        throw new InvalidStationAssessmentAiExplanationRequest();
      }
      if (character === "\\") {
        this.#offset += 1;
        const escape = this.source[this.#offset];
        if (escape === "u") {
          if (
            !/^[0-9a-fA-F]{4}$/.test(
              this.source.slice(this.#offset + 1, this.#offset + 5),
            )
          ) {
            throw new InvalidStationAssessmentAiExplanationRequest();
          }
          this.#offset += 5;
          continue;
        }
        if (escape === undefined || !'"\\/bfnrt'.includes(escape)) {
          throw new InvalidStationAssessmentAiExplanationRequest();
        }
      }
      this.#offset += 1;
    }
    throw new InvalidStationAssessmentAiExplanationRequest();
  }

  private skipWhitespace(): void {
    while (
      this.#offset < this.source.length &&
      " \t\n\r".includes(this.source[this.#offset])
    ) {
      this.#offset += 1;
    }
  }

  private expect(expected: string): void {
    if (this.peek() !== expected) {
      throw new InvalidStationAssessmentAiExplanationRequest();
    }
    this.#offset += 1;
  }

  private peek(): string | undefined {
    return this.source[this.#offset];
  }
}
