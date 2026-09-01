import {
  completedAssistantOutputText,
  createOpenAiResponsesOutputText,
  defaultOpenAiTimeoutMs,
  openAiDefaultModel,
  openAiResponsesEndpoint,
  OpenAiResponsesFailure,
  type OpenAiResponsesFailureReason,
  readBoundedUtf8Body,
  sha256Hex,
} from "../_shared/openai_responses.ts";

export { openAiResponsesEndpoint, readBoundedUtf8Body, sha256Hex };

export const businessEvaluationAiAdvisorModel = openAiDefaultModel;
export const businessEvaluationAiAdvisorPromptVersion =
  "module3-business-advisor-v1";
export const maximumAdvisorRequestBodyBytes = 4_096;
export const maximumOpenAiResponseBytes = 32_768;
export const openAiTimeoutMs = defaultOpenAiTimeoutMs;
export const maximumOpenAiOutputTokens = 1_200;

const advisorDriverTypes = ["strength", "risk"] as const;
const advisorActionPriorities = ["high", "medium", "low"] as const;

export type AiBusinessAdvisorRequest = {
  evaluationId: string;
};

export type AiBusinessAdvisorInsight = {
  executiveSummary: string;
  drivers: Array<{
    type: "strength" | "risk";
    factor: string;
    evidence: string;
  }>;
  actions: Array<{
    priority: "high" | "medium" | "low";
    action: string;
    reason: string;
  }>;
  scenarioToTest: {
    variable:
      | "daily_customers"
      | "average_litres"
      | "fuel_margin"
      | "fixed_operating_cost"
      | "initial_investment";
    direction: "increase" | "decrease" | "review";
    reason: string;
  };
  dataLimitations: string[];
  disclaimer: string;
};

export type CanonicalBusinessEvaluationAdvisorInput = {
  assumptions: {
    fuel_price: number;
    fuel_purchase_cost: number;
    daily_customers: number;
    average_litres: number;
    monthly_rental: number;
    monthly_staff_salary: number;
    monthly_utilities: number;
    monthly_maintenance: number;
    monthly_other_cost: number;
    initial_investment: number;
  };
  deterministic_results: {
    monthly_sales_volume: number;
    monthly_revenue: number;
    monthly_fuel_cost: number;
    monthly_operating_cost: number;
    monthly_profit: number;
    profit_margin: number;
    roi: number;
    break_even_months: number | null;
    profitability_score: number;
    profitability_category: string;
    recommendation: string;
    explanation: string;
  };
};

export class InvalidAiBusinessAdvisorRequest extends Error {
  constructor() {
    super("Invalid AI business advisor request.");
    this.name = "InvalidAiBusinessAdvisorRequest";
  }
}

export class InvalidStoredBusinessEvaluation extends Error {
  constructor() {
    super("Stored business evaluation is invalid.");
    this.name = "InvalidStoredBusinessEvaluation";
  }
}

export class InvalidAiBusinessAdvisorInsight extends Error {
  constructor() {
    super("AI business advisor output is invalid.");
    this.name = "InvalidAiBusinessAdvisorInsight";
  }
}

export class AiBusinessAdvisorUnavailable extends Error {
  constructor() {
    super("AI business advisor is unavailable.");
    this.name = "AiBusinessAdvisorUnavailable";
  }
}

export type OpenAiBusinessAdvisorProviderFailureReason =
  | OpenAiResponsesFailureReason
  | "provider_insight_invalid";

export class OpenAiBusinessAdvisorProviderFailure
  extends AiBusinessAdvisorUnavailable {
  readonly reason: OpenAiBusinessAdvisorProviderFailureReason;
  readonly httpStatus: number | undefined;

  constructor(
    reason: OpenAiBusinessAdvisorProviderFailureReason,
    httpStatus?: number,
  ) {
    super();
    this.name = "OpenAiBusinessAdvisorProviderFailure";
    this.reason = reason;
    this.httpStatus = httpStatus;
  }
}

export function parseAiBusinessAdvisorRequest(
  value: unknown,
): AiBusinessAdvisorRequest {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new InvalidAiBusinessAdvisorRequest();
  }

  const record = value as Record<string, unknown>;
  const keys = Object.keys(record);
  if (keys.length !== 1 || keys[0] !== "evaluation_id") {
    throw new InvalidAiBusinessAdvisorRequest();
  }

  return { evaluationId: parseUuid(record.evaluation_id) };
}

export function parseAiBusinessAdvisorRequestJson(
  rawJson: string,
): AiBusinessAdvisorRequest {
  const cursor = new ExactAiBusinessAdvisorJsonCursor(rawJson);
  const record = cursor.readExactStringObject();
  cursor.requireEnd();
  return parseAiBusinessAdvisorRequest(record);
}

export async function parseBoundedAiBusinessAdvisorRequest(
  request: Request,
): Promise<AiBusinessAdvisorRequest> {
  const rawJson = await readBoundedUtf8Body(
    request.body,
    request.headers.get("content-length"),
    maximumAdvisorRequestBodyBytes,
    () => new InvalidAiBusinessAdvisorRequest(),
  );
  return parseAiBusinessAdvisorRequestJson(rawJson);
}

export function createCanonicalBusinessEvaluationAdvisorInput(value: {
  fuelPrice: unknown;
  fuelPurchaseCost: unknown;
  dailyCustomers: unknown;
  averageLitres: unknown;
  monthlyRental: unknown;
  monthlyStaffSalary: unknown;
  monthlyUtilities: unknown;
  monthlyMaintenance: unknown;
  monthlyOtherCost: unknown;
  initialInvestment: unknown;
  monthlySalesVolume: unknown;
  monthlyRevenue: unknown;
  monthlyFuelCost: unknown;
  monthlyOperatingCost: unknown;
  monthlyProfit: unknown;
  profitMargin: unknown;
  roi: unknown;
  breakEvenMonths: unknown;
  profitabilityScore: unknown;
  profitabilityCategory: unknown;
  recommendation: unknown;
  explanation: unknown;
}): CanonicalBusinessEvaluationAdvisorInput {
  const fuelPrice = finiteNonNegative(value.fuelPrice);
  const fuelPurchaseCost = finiteNonNegative(value.fuelPurchaseCost);
  const dailyCustomers = finiteNonNegativeInteger(value.dailyCustomers);
  const averageLitres = finiteNonNegative(value.averageLitres);
  const monthlyRental = finiteNonNegative(value.monthlyRental);
  const monthlyStaffSalary = finiteNonNegative(value.monthlyStaffSalary);
  const monthlyUtilities = finiteNonNegative(value.monthlyUtilities);
  const monthlyMaintenance = finiteNonNegative(value.monthlyMaintenance);
  const monthlyOtherCost = finiteNonNegative(value.monthlyOtherCost);
  const initialInvestment = finiteNonNegative(value.initialInvestment);

  if (fuelPrice <= fuelPurchaseCost) {
    throw new InvalidStoredBusinessEvaluation();
  }

  const monthlySalesVolume = finiteNonNegative(value.monthlySalesVolume);
  const monthlyRevenue = finiteNonNegative(value.monthlyRevenue);
  const monthlyFuelCost = finiteNonNegative(value.monthlyFuelCost);
  const monthlyOperatingCost = finiteNonNegative(value.monthlyOperatingCost);
  const monthlyProfit = finiteNumber(value.monthlyProfit);
  const profitMargin = finiteNumber(value.profitMargin);
  const roi = finiteNumber(value.roi);
  const breakEvenMonths = value.breakEvenMonths === null
    ? null
    : finiteNonNegative(value.breakEvenMonths);
  const profitabilityScore = finiteNumber(value.profitabilityScore);
  if (profitabilityScore < 0 || profitabilityScore > 100) {
    throw new InvalidStoredBusinessEvaluation();
  }

  return {
    assumptions: {
      fuel_price: fuelPrice,
      fuel_purchase_cost: fuelPurchaseCost,
      daily_customers: dailyCustomers,
      average_litres: averageLitres,
      monthly_rental: monthlyRental,
      monthly_staff_salary: monthlyStaffSalary,
      monthly_utilities: monthlyUtilities,
      monthly_maintenance: monthlyMaintenance,
      monthly_other_cost: monthlyOtherCost,
      initial_investment: initialInvestment,
    },
    deterministic_results: {
      monthly_sales_volume: monthlySalesVolume,
      monthly_revenue: monthlyRevenue,
      monthly_fuel_cost: monthlyFuelCost,
      monthly_operating_cost: monthlyOperatingCost,
      monthly_profit: monthlyProfit,
      profit_margin: profitMargin,
      roi,
      break_even_months: breakEvenMonths,
      profitability_score: profitabilityScore,
      profitability_category: storedBoundedString(
        value.profitabilityCategory,
        80,
      ),
      recommendation: storedBoundedString(value.recommendation, 1_000),
      explanation: storedBoundedString(value.explanation, 2_000),
    },
  };
}

export const businessEvaluationAiInsightJsonSchema = {
  type: "object",
  additionalProperties: false,
  required: [
    "executive_summary",
    "drivers",
    "actions",
    "scenario_to_test",
    "data_limitations",
    "disclaimer",
  ],
  properties: {
    executive_summary: { type: "string", minLength: 1, maxLength: 1_000 },
    drivers: {
      type: "array",
      minItems: 1,
      maxItems: 6,
      items: {
        type: "object",
        additionalProperties: false,
        required: ["type", "factor", "evidence"],
        properties: {
          type: { type: "string", enum: ["strength", "risk"] },
          factor: { type: "string", minLength: 1, maxLength: 240 },
          evidence: { type: "string", minLength: 1, maxLength: 360 },
        },
      },
    },
    actions: {
      type: "array",
      minItems: 3,
      maxItems: 3,
      items: {
        type: "object",
        additionalProperties: false,
        required: ["priority", "action", "reason"],
        properties: {
          priority: { type: "string", enum: ["high", "medium", "low"] },
          action: { type: "string", minLength: 1, maxLength: 240 },
          reason: { type: "string", minLength: 1, maxLength: 360 },
        },
      },
    },
    scenario_to_test: {
      type: "object",
      additionalProperties: false,
      required: ["variable", "direction", "reason"],
      properties: {
        variable: {
          type: "string",
          enum: [
            "daily_customers",
            "average_litres",
            "fuel_margin",
            "fixed_operating_cost",
            "initial_investment",
          ],
        },
        direction: { type: "string", enum: ["increase", "decrease", "review"] },
        reason: { type: "string", minLength: 1, maxLength: 360 },
      },
    },
    data_limitations: {
      type: "array",
      minItems: 0,
      maxItems: 6,
      items: { type: "string", minLength: 1, maxLength: 240 },
    },
    disclaimer: { type: "string", minLength: 1, maxLength: 500 },
  },
} as const;

export function buildOpenAiBusinessAdvisorRequest(
  input: CanonicalBusinessEvaluationAdvisorInput,
): Record<string, unknown> {
  return {
    model: businessEvaluationAiAdvisorModel,
    // Explicitly disable provider-side response storage. The app stores only
    // the validated advisory JSON in its own RLS-protected table.
    store: false,
    reasoning: { effort: "low" },
    max_output_tokens: maximumOpenAiOutputTokens,
    tools: [],
    tool_choice: "none",
    parallel_tool_calls: false,
    instructions:
      "You are an advisory business evaluator. Explain only the supplied deterministic Module 3 assumptions and results. Do not recalculate, alter, or dispute any supplied values. Do not claim guaranteed outcomes, invent market facts, or provide legal, investment, or regulatory advice. Return only the required structured output.",
    input: JSON.stringify(input),
    text: {
      verbosity: "low",
      format: {
        type: "json_schema",
        name: "business_evaluation_ai_insight",
        strict: true,
        schema: businessEvaluationAiInsightJsonSchema,
      },
    },
  };
}

export function createOpenAiBusinessAdvisor(dependencies: {
  http: (url: string, init: RequestInit) => Promise<Response>;
  apiKey: string;
  timeoutMs?: number;
}): {
  create(
    input: CanonicalBusinessEvaluationAdvisorInput,
  ): Promise<AiBusinessAdvisorInsight>;
} {
  return {
    async create(input) {
      try {
        const outputText = await createOpenAiResponsesOutputText({
          http: dependencies.http,
          apiKey: dependencies.apiKey,
          request: buildOpenAiBusinessAdvisorRequest(input),
          timeoutMs: dependencies.timeoutMs ?? openAiTimeoutMs,
          maximumResponseBytes: maximumOpenAiResponseBytes,
        });
        return parseAiBusinessAdvisorInsight(JSON.parse(outputText));
      } catch (error) {
        if (error instanceof OpenAiBusinessAdvisorProviderFailure) throw error;
        if (error instanceof OpenAiResponsesFailure) {
          throw new OpenAiBusinessAdvisorProviderFailure(
            error.reason,
            error.httpStatus,
          );
        }
        throw new OpenAiBusinessAdvisorProviderFailure(
          "provider_insight_invalid",
        );
      }
    },
  };
}

export function parseOpenAiBusinessAdvisorResponse(
  value: unknown,
): AiBusinessAdvisorInsight {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new InvalidAiBusinessAdvisorInsight();
  }
  let outputText: string;
  try {
    outputText = completedAssistantOutputText(value);
  } catch (error) {
    if (error instanceof OpenAiResponsesFailure) {
      throw new OpenAiBusinessAdvisorProviderFailure(
        error.reason,
        error.httpStatus,
      );
    }
    throw error;
  }
  if (
    new TextEncoder().encode(outputText).byteLength > maximumOpenAiResponseBytes
  ) {
    throw new OpenAiBusinessAdvisorProviderFailure(
      "provider_response_too_large",
    );
  }

  try {
    return parseAiBusinessAdvisorInsight(JSON.parse(outputText));
  } catch (_) {
    throw new OpenAiBusinessAdvisorProviderFailure("provider_insight_invalid");
  }
}

export function parseAiBusinessAdvisorInsight(
  value: unknown,
): AiBusinessAdvisorInsight {
  const insight = exactObject(value, [
    "executive_summary",
    "drivers",
    "actions",
    "scenario_to_test",
    "data_limitations",
    "disclaimer",
  ]);
  const drivers = boundedArray(insight.drivers, 1, 6).map((driver) => {
    const parsed = exactObject(driver, ["type", "factor", "evidence"]);
    return {
      type: boundedAdvisorEnum(parsed.type, advisorDriverTypes),
      factor: boundedString(parsed.factor, 240),
      evidence: boundedString(parsed.evidence, 360),
    };
  });
  const actions = boundedArray(insight.actions, 3, 3).map((action) => {
    const parsed = exactObject(action, ["priority", "action", "reason"]);
    return {
      priority: boundedAdvisorEnum(parsed.priority, advisorActionPriorities),
      action: boundedString(parsed.action, 240),
      reason: boundedString(parsed.reason, 360),
    };
  });
  const scenario = exactObject(insight.scenario_to_test, [
    "variable",
    "direction",
    "reason",
  ]);
  if (
    scenario.variable !== "daily_customers" &&
    scenario.variable !== "average_litres" &&
    scenario.variable !== "fuel_margin" &&
    scenario.variable !== "fixed_operating_cost" &&
    scenario.variable !== "initial_investment"
  ) {
    throw new InvalidAiBusinessAdvisorInsight();
  }
  if (
    scenario.direction !== "increase" && scenario.direction !== "decrease" &&
    scenario.direction !== "review"
  ) {
    throw new InvalidAiBusinessAdvisorInsight();
  }

  return {
    executiveSummary: boundedString(insight.executive_summary, 1_000),
    drivers,
    actions,
    scenarioToTest: {
      variable: scenario.variable,
      direction: scenario.direction,
      reason: boundedString(scenario.reason, 360),
    },
    dataLimitations: boundedArray(insight.data_limitations, 0, 6).map((item) =>
      boundedString(item, 240)
    ),
    disclaimer: boundedString(insight.disclaimer, 500),
  };
}

function parseUuid(value: unknown): string {
  if (
    typeof value !== "string" ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(value)
  ) {
    throw new InvalidAiBusinessAdvisorRequest();
  }
  return value.toLowerCase();
}

function finiteNumber(value: unknown): number {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    throw new InvalidStoredBusinessEvaluation();
  }
  return value;
}

function finiteNonNegative(value: unknown): number {
  const number = finiteNumber(value);
  if (number < 0) throw new InvalidStoredBusinessEvaluation();
  return number;
}

function finiteNonNegativeInteger(value: unknown): number {
  const number = finiteNonNegative(value);
  if (!Number.isInteger(number)) throw new InvalidStoredBusinessEvaluation();
  return number;
}

function boundedString(value: unknown, maximumLength: number): string {
  if (
    typeof value !== "string" || value.trim() === "" ||
    value.length > maximumLength
  ) {
    throw new InvalidAiBusinessAdvisorInsight();
  }
  return value;
}

function boundedAdvisorEnum<const Values extends readonly string[]>(
  value: unknown,
  allowedValues: Values,
): Values[number] {
  for (const allowedValue of allowedValues) {
    if (value === allowedValue) return allowedValue;
  }
  throw new InvalidAiBusinessAdvisorInsight();
}

function storedBoundedString(value: unknown, maximumLength: number): string {
  if (
    typeof value !== "string" || value.trim() === "" ||
    value.length > maximumLength
  ) {
    throw new InvalidStoredBusinessEvaluation();
  }
  return value;
}

function boundedArray(
  value: unknown,
  minimum: number,
  maximum: number,
): unknown[] {
  if (
    !Array.isArray(value) || value.length < minimum || value.length > maximum
  ) {
    throw new InvalidAiBusinessAdvisorInsight();
  }
  return value;
}

function exactObject(value: unknown, keys: string[]): Record<string, unknown> {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new InvalidAiBusinessAdvisorInsight();
  }
  const record = value as Record<string, unknown>;
  const actual = Object.keys(record).sort();
  const expected = [...keys].sort();
  if (
    actual.length !== expected.length ||
    actual.some((key, index) => key !== expected[index])
  ) {
    throw new InvalidAiBusinessAdvisorInsight();
  }
  return record;
}

class ExactAiBusinessAdvisorJsonCursor {
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
    if (this.peek() === "}") throw new InvalidAiBusinessAdvisorRequest();
    while (true) {
      this.skipWhitespace();
      const key = this.readString();
      if (seen.has(key)) throw new InvalidAiBusinessAdvisorRequest();
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
      throw new InvalidAiBusinessAdvisorRequest();
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
          throw new InvalidAiBusinessAdvisorRequest();
        }
      }
      if (character.charCodeAt(0) < 0x20) {
        throw new InvalidAiBusinessAdvisorRequest();
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
            throw new InvalidAiBusinessAdvisorRequest();
          }
          this.#offset += 5;
          continue;
        }
        if (escape === undefined || !'"\\/bfnrt'.includes(escape)) {
          throw new InvalidAiBusinessAdvisorRequest();
        }
      }
      this.#offset += 1;
    }
    throw new InvalidAiBusinessAdvisorRequest();
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
    if (this.peek() !== expected) throw new InvalidAiBusinessAdvisorRequest();
    this.#offset += 1;
  }

  private peek(): string | undefined {
    return this.source[this.#offset];
  }
}
