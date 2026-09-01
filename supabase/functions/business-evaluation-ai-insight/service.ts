import {
  type AiBusinessAdvisorInsight,
  type AiBusinessAdvisorRequest,
  AiBusinessAdvisorUnavailable,
  businessEvaluationAiAdvisorModel,
  businessEvaluationAiAdvisorPromptVersion,
  type CanonicalBusinessEvaluationAdvisorInput,
  createCanonicalBusinessEvaluationAdvisorInput,
  InvalidAiBusinessAdvisorInsight,
  InvalidAiBusinessAdvisorRequest,
  InvalidStoredBusinessEvaluation,
  OpenAiBusinessAdvisorProviderFailure,
  type OpenAiBusinessAdvisorProviderFailureReason,
  parseAiBusinessAdvisorInsight,
  parseBoundedAiBusinessAdvisorRequest,
  sha256Hex,
} from "./business_evaluation_ai_insight.ts";

export type HttpClient = (url: string, init: RequestInit) => Promise<Response>;

export type StoredBusinessEvaluation = {
  id: string;
  userId: string;
  updatedAt: string;
  advisorInput: CanonicalBusinessEvaluationAdvisorInput;
};

export type StoredBusinessEvaluationAiInsight = {
  evaluationId: string;
  insight: AiBusinessAdvisorInsight;
  model: string;
  promptVersion: string;
  inputHash: string;
  sourceEvaluationUpdatedAt: string;
  generatedAt: string;
};

export type PublicAiBusinessAdvisorInsight = {
  executive_summary: string;
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
  scenario_to_test: {
    variable:
      | "daily_customers"
      | "average_litres"
      | "fuel_margin"
      | "fixed_operating_cost"
      | "initial_investment";
    direction: "increase" | "decrease" | "review";
    reason: string;
  };
  data_limitations: string[];
  disclaimer: string;
};

export type AiBusinessAdvisorPublicResponse = {
  cache_status: "generated" | "cached";
  insight: PublicAiBusinessAdvisorInsight;
  model: typeof businessEvaluationAiAdvisorModel;
  prompt_version: string;
  generated_at: string;
  source_evaluation_updated_at: string;
};

export const aiBusinessAdvisorRuntimeFailureEvent =
  "ai_advisor_runtime_failure";

export type AiBusinessAdvisorRuntimeFailureStage =
  | "auth_unavailable"
  | "evaluation_read_failed"
  | "insight_read_failed"
  | "provider_generation_failed"
  | "insight_upsert_failed";

export type AiBusinessAdvisorRuntimeFailureLogEvent = {
  event: typeof aiBusinessAdvisorRuntimeFailureEvent;
  stage: AiBusinessAdvisorRuntimeFailureStage;
  provider_failure_reason?: OpenAiBusinessAdvisorProviderFailureReason;
  provider_http_status?: number;
  elapsed_ms: number;
  request_id: string;
};

export interface EvaluationReader {
  read(
    evaluationId: string,
    accessToken: string,
  ): Promise<StoredBusinessEvaluation | null>;
}

export interface AiInsightStore {
  get(evaluationId: string): Promise<StoredBusinessEvaluationAiInsight | null>;
  upsert(value: {
    evaluation: StoredBusinessEvaluation;
    insight: AiBusinessAdvisorInsight;
    inputHash: string;
    generatedAt: string;
  }): Promise<StoredBusinessEvaluationAiInsight>;
}

export interface OpenAiBusinessAdvisor {
  create(
    input: CanonicalBusinessEvaluationAdvisorInput,
  ): Promise<AiBusinessAdvisorInsight>;
}

export interface AiBusinessAdvisorHandlerDependencies {
  authenticate(accessToken: string): Promise<boolean>;
  evaluationReader: EvaluationReader;
  insightStore: AiInsightStore;
  advisor: OpenAiBusinessAdvisor;
  now?: () => Date;
  requestId?: () => string;
  nowMilliseconds?: () => number;
  logger?: (event: AiBusinessAdvisorRuntimeFailureLogEvent) => void;
}

export class AuthenticationUnavailable extends Error {
  constructor() {
    super("Supabase authentication is unavailable.");
    this.name = "AuthenticationUnavailable";
  }
}

class AiBusinessAdvisorRuntimeFailure extends AiBusinessAdvisorUnavailable {
  readonly stage: AiBusinessAdvisorRuntimeFailureStage;
  readonly providerFailureReason:
    | OpenAiBusinessAdvisorProviderFailureReason
    | undefined;
  readonly providerHttpStatus: number | undefined;

  constructor(
    stage: AiBusinessAdvisorRuntimeFailureStage,
    providerFailure?: OpenAiBusinessAdvisorProviderFailure,
  ) {
    super();
    this.stage = stage;
    this.providerFailureReason = providerFailure?.reason;
    this.providerHttpStatus = providerFailure?.httpStatus;
  }
}

export interface SupabaseAuthDependencies {
  http: HttpClient;
  supabaseUrl: string;
  supabaseAnonKey: string;
  timeoutMs?: number;
}

export async function verifySupabaseAccessToken(
  accessToken: string,
  dependencies: SupabaseAuthDependencies,
): Promise<boolean> {
  const controller = new AbortController();
  const timeout = setTimeout(
    () => controller.abort(),
    dependencies.timeoutMs ?? 5_000,
  );
  try {
    const response = await dependencies.http(
      `${dependencies.supabaseUrl}/auth/v1/user`,
      {
        headers: {
          apikey: dependencies.supabaseAnonKey,
          authorization: `Bearer ${accessToken}`,
        },
        signal: controller.signal,
      },
    );
    if (response.status >= 500) throw new AuthenticationUnavailable();
    if (!response.ok) return false;
    const user = await response.json();
    if (
      user === null || typeof user !== "object" || Array.isArray(user) ||
      typeof (user as Record<string, unknown>).id !== "string" ||
      !(user as Record<string, unknown>).id
    ) {
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

export function createAiBusinessAdvisorHandler(
  dependencies: AiBusinessAdvisorHandlerDependencies,
): (request: Request) => Promise<Response> {
  return async (request) => {
    const requestId = (dependencies.requestId ?? (() => crypto.randomUUID()))();
    const nowMilliseconds = dependencies.nowMilliseconds ?? (() => Date.now());
    const startedAtMilliseconds = nowMilliseconds();
    const response = (
      value: unknown,
      status = 200,
      headers: Record<string, string> = {},
    ) =>
      jsonResponse(value, status, {
        ...headers,
        "x-ai-advisor-request-id": requestId,
      });
    const logRuntimeFailure = (
      stage: AiBusinessAdvisorRuntimeFailureStage,
      providerFailureReason?: OpenAiBusinessAdvisorProviderFailureReason,
      providerHttpStatus?: number,
    ) => {
      const event: AiBusinessAdvisorRuntimeFailureLogEvent = {
        event: aiBusinessAdvisorRuntimeFailureEvent,
        stage,
        ...(providerFailureReason === undefined
          ? {}
          : { provider_failure_reason: providerFailureReason }),
        ...(providerHttpStatus === undefined
          ? {}
          : { provider_http_status: providerHttpStatus }),
        elapsed_ms: Math.max(
          0,
          Math.round(nowMilliseconds() - startedAtMilliseconds),
        ),
        request_id: requestId,
      };
      try {
        (dependencies.logger ?? defaultRuntimeLogger)(event);
      } catch (_) {
        // Logging must not replace a neutral public response.
      }
    };

    if (request.method !== "POST") {
      return response({ error: "method_not_allowed" }, 405, {
        Allow: "POST",
      });
    }

    const accessToken = parseBearerToken(request.headers.get("authorization"));
    if (accessToken === null) {
      return response({ error: "unauthorized" }, 401);
    }

    try {
      if (!(await dependencies.authenticate(accessToken))) {
        return response({ error: "unauthorized" }, 401);
      }
    } catch (_) {
      logRuntimeFailure("auth_unavailable");
      return response({ error: "authentication_unavailable" }, 503);
    }

    try {
      const advisorRequest = await parseBoundedAiBusinessAdvisorRequest(
        request,
      );
      const result = await loadAiBusinessAdvisorInsight(
        advisorRequest,
        accessToken,
        dependencies,
      );
      return response(result);
    } catch (error) {
      if (error instanceof InvalidAiBusinessAdvisorRequest) {
        return response({ error: "invalid_request" }, 400);
      }
      if (error instanceof EvaluationNotFound) {
        return response({ error: "evaluation_not_found" }, 404);
      }
      if (error instanceof AiBusinessAdvisorRuntimeFailure) {
        logRuntimeFailure(
          error.stage,
          error.providerFailureReason,
          error.providerHttpStatus,
        );
      }
      return response({ error: "advisor_unavailable" }, 503);
    }
  };
}

export async function loadAiBusinessAdvisorInsight(
  request: AiBusinessAdvisorRequest,
  accessToken: string,
  dependencies: AiBusinessAdvisorHandlerDependencies,
): Promise<AiBusinessAdvisorPublicResponse> {
  let evaluation: StoredBusinessEvaluation | null;
  try {
    evaluation = await dependencies.evaluationReader.read(
      request.evaluationId,
      accessToken,
    );
  } catch (_) {
    throw new AiBusinessAdvisorRuntimeFailure("evaluation_read_failed");
  }
  if (evaluation === null) throw new EvaluationNotFound();

  const inputHash = await sha256Hex(evaluation.advisorInput);
  let existing: StoredBusinessEvaluationAiInsight | null;
  try {
    existing = await dependencies.insightStore.get(evaluation.id);
  } catch (_) {
    throw new AiBusinessAdvisorRuntimeFailure("insight_read_failed");
  }
  if (
    existing !== null &&
    existing.inputHash === inputHash &&
    existing.model === businessEvaluationAiAdvisorModel &&
    existing.promptVersion === businessEvaluationAiAdvisorPromptVersion
  ) {
    return publicResponse("cached", existing);
  }

  let insight: AiBusinessAdvisorInsight;
  try {
    insight = await dependencies.advisor.create(evaluation.advisorInput);
  } catch (error) {
    throw new AiBusinessAdvisorRuntimeFailure(
      "provider_generation_failed",
      error instanceof OpenAiBusinessAdvisorProviderFailure ? error : undefined,
    );
  }

  try {
    const stored = await dependencies.insightStore.upsert({
      evaluation,
      insight,
      inputHash,
      generatedAt: (dependencies.now ?? (() => new Date()))().toISOString(),
    });
    return publicResponse("generated", stored);
  } catch (_) {
    throw new AiBusinessAdvisorRuntimeFailure("insight_upsert_failed");
  }
}

export function parseStoredBusinessEvaluation(
  value: unknown,
): StoredBusinessEvaluation {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new InvalidStoredBusinessEvaluation();
  }
  const row = value as Record<string, unknown>;
  const id = parseUuid(row.id);
  const userId = parseUuid(row.user_id);
  const updatedAt = parseTimestamp(row.updated_at);
  return {
    id,
    userId,
    updatedAt,
    advisorInput: createCanonicalBusinessEvaluationAdvisorInput({
      fuelPrice: row.fuel_price,
      fuelPurchaseCost: row.fuel_purchase_cost,
      dailyCustomers: row.daily_customers,
      averageLitres: row.average_litres,
      monthlyRental: row.monthly_rental,
      monthlyStaffSalary: row.monthly_staff_salary,
      monthlyUtilities: row.monthly_utilities,
      monthlyMaintenance: row.monthly_maintenance,
      monthlyOtherCost: row.monthly_other_cost,
      initialInvestment: row.initial_investment,
      monthlySalesVolume: row.monthly_sales_volume,
      monthlyRevenue: row.monthly_revenue,
      monthlyFuelCost: row.monthly_fuel_cost,
      monthlyOperatingCost: row.monthly_operating_cost,
      monthlyProfit: row.monthly_profit,
      profitMargin: row.profit_margin,
      roi: row.roi,
      breakEvenMonths: row.break_even_months,
      profitabilityScore: row.profitability_score,
      profitabilityCategory: row.profitability_category,
      recommendation: row.recommendation,
      explanation: row.explanation,
    }),
  };
}

export function parseStoredBusinessEvaluationAiInsight(
  value: unknown,
): StoredBusinessEvaluationAiInsight {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new InvalidAiBusinessAdvisorInsight();
  }
  const row = value as Record<string, unknown>;
  const model = row.model;
  const promptVersion = row.prompt_version;
  const inputHash = row.input_hash;
  if (
    model !== businessEvaluationAiAdvisorModel ||
    typeof promptVersion !== "string" ||
    !/^[A-Za-z0-9._-]{1,80}$/.test(promptVersion) ||
    typeof inputHash !== "string" ||
    !/^[0-9a-f]{64}$/.test(inputHash)
  ) {
    throw new InvalidAiBusinessAdvisorInsight();
  }
  return {
    evaluationId: parseUuid(row.evaluation_id),
    insight: parseAiBusinessAdvisorInsight(row.insight),
    model,
    promptVersion,
    inputHash,
    sourceEvaluationUpdatedAt: parseTimestamp(row.source_evaluation_updated_at),
    generatedAt: parseTimestamp(row.generated_at),
  };
}

export function parseBearerToken(value: string | null): string | null {
  if (value === null) return null;
  const match = /^Bearer\s+(.+)$/i.exec(value);
  return match?.[1]?.trim() || null;
}

class EvaluationNotFound extends Error {}

function publicResponse(
  cacheStatus: "generated" | "cached",
  insight: StoredBusinessEvaluationAiInsight,
): AiBusinessAdvisorPublicResponse {
  return {
    cache_status: cacheStatus,
    insight: toPublicInsight(insight.insight),
    model: businessEvaluationAiAdvisorModel,
    prompt_version: insight.promptVersion,
    generated_at: insight.generatedAt,
    source_evaluation_updated_at: insight.sourceEvaluationUpdatedAt,
  };
}

function toPublicInsight(
  insight: AiBusinessAdvisorInsight,
): PublicAiBusinessAdvisorInsight {
  return {
    executive_summary: insight.executiveSummary,
    drivers: insight.drivers.map((driver) => ({
      type: driver.type,
      factor: driver.factor,
      evidence: driver.evidence,
    })),
    actions: insight.actions.map((action) => ({
      priority: action.priority,
      action: action.action,
      reason: action.reason,
    })),
    scenario_to_test: {
      variable: insight.scenarioToTest.variable,
      direction: insight.scenarioToTest.direction,
      reason: insight.scenarioToTest.reason,
    },
    data_limitations: [...insight.dataLimitations],
    disclaimer: insight.disclaimer,
  };
}

function parseUuid(value: unknown): string {
  if (
    typeof value !== "string" ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(value)
  ) {
    throw new InvalidStoredBusinessEvaluation();
  }
  return value.toLowerCase();
}

function parseTimestamp(value: unknown): string {
  if (typeof value !== "string" || !Number.isFinite(Date.parse(value))) {
    throw new InvalidStoredBusinessEvaluation();
  }
  return value;
}

function jsonResponse(
  value: unknown,
  status = 200,
  headers: HeadersInit = {},
): Response {
  return new Response(JSON.stringify(value), {
    status,
    headers: { "content-type": "application/json", ...headers },
  });
}

function defaultRuntimeLogger(
  event: AiBusinessAdvisorRuntimeFailureLogEvent,
): void {
  console.log(JSON.stringify(event));
}
