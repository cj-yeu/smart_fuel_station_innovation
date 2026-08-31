import {
  type AiBusinessAdvisorInsight,
  businessEvaluationAiAdvisorModel,
  businessEvaluationAiAdvisorPromptVersion,
  createOpenAiBusinessAdvisor,
} from "./business_evaluation_ai_insight.ts";
import {
  type AiInsightStore,
  type EvaluationReader,
  createAiBusinessAdvisorHandler,
  parseStoredBusinessEvaluation,
  parseStoredBusinessEvaluationAiInsight,
  verifySupabaseAccessToken,
} from "./service.ts";

const supabaseUrl = requiredEnvironment("SUPABASE_URL");
const supabaseAnonKey = requiredEnvironment("SUPABASE_ANON_KEY");
const supabaseServiceRoleKey = requiredEnvironment("SUPABASE_SERVICE_ROLE_KEY");
const openAiApiKey = requiredEnvironment("OPENAI_API_KEY");

Deno.serve(createAiBusinessAdvisorHandler({
  authenticate: (accessToken) => verifySupabaseAccessToken(accessToken, {
    http: fetch,
    supabaseUrl,
    supabaseAnonKey,
  }),
  evaluationReader: createEvaluationReader(),
  insightStore: createInsightStore(),
  advisor: createOpenAiBusinessAdvisor({ http: fetch, apiKey: openAiApiKey }),
}));

function createEvaluationReader(): EvaluationReader {
  return {
    async read(evaluationId, accessToken) {
      const response = await fetch(
        `${supabaseUrl}/rest/v1/business_evaluations?select=${encodeURIComponent(
          evaluationSelect,
        )}&id=eq.${encodeURIComponent(evaluationId)}&limit=2`,
        {
          headers: callerHeaders(accessToken),
        },
      );
      if (!response.ok) throw new Error("evaluation unavailable");
      const rows = await response.json();
      if (!Array.isArray(rows)) throw new Error("evaluation response is invalid");
      if (rows.length === 0) return null;
      if (rows.length !== 1) throw new Error("evaluation response is ambiguous");
      return parseStoredBusinessEvaluation(rows[0]);
    },
  };
}

function createInsightStore(): AiInsightStore {
  return {
    async get(evaluationId) {
      const response = await trustedRequest(
        `/rest/v1/business_evaluation_ai_insights?select=${encodeURIComponent(
          insightSelect,
        )}&evaluation_id=eq.${encodeURIComponent(evaluationId)}&limit=2`,
        { method: "GET" },
      );
      const rows = await response.json();
      if (!Array.isArray(rows)) throw new Error("insight response is invalid");
      if (rows.length === 0) return null;
      if (rows.length !== 1) throw new Error("insight response is ambiguous");
      return parseStoredBusinessEvaluationAiInsight(rows[0]);
    },
    async upsert(value) {
      const response = await trustedRequest(
        "/rest/v1/business_evaluation_ai_insights?on_conflict=evaluation_id",
        {
          method: "POST",
          headers: {
            "content-type": "application/json",
            prefer: "resolution=merge-duplicates,return=representation",
          },
          body: JSON.stringify({
            evaluation_id: value.evaluation.id,
            // The database trigger derives this from the linked evaluation.
            // It is never accepted from the public request or sent to OpenAI.
            user_id: value.evaluation.userId,
            insight: toStoredInsight(value.insight),
            model: businessEvaluationAiAdvisorModel,
            prompt_version: businessEvaluationAiAdvisorPromptVersion,
            input_hash: value.inputHash,
            source_evaluation_updated_at: value.evaluation.updatedAt,
            generated_at: value.generatedAt,
          }),
        },
      );
      const rows = await response.json();
      if (!Array.isArray(rows) || rows.length !== 1) {
        throw new Error("insight upsert response is invalid");
      }
      return parseStoredBusinessEvaluationAiInsight(rows[0]);
    },
  };
}

function toStoredInsight(insight: AiBusinessAdvisorInsight): Record<string, unknown> {
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

async function trustedRequest(path: string, init: RequestInit): Promise<Response> {
  const response = await fetch(`${supabaseUrl}${path}`, {
    ...init,
    headers: {
      apikey: supabaseServiceRoleKey,
      authorization: `Bearer ${supabaseServiceRoleKey}`,
      ...init.headers,
    },
  });
  if (!response.ok) throw new Error("insight storage is unavailable");
  return response;
}

function callerHeaders(accessToken: string): HeadersInit {
  return {
    apikey: supabaseAnonKey,
    authorization: `Bearer ${accessToken}`,
  };
}

function requiredEnvironment(name: string): string {
  const value = Deno.env.get(name);
  if (value === undefined || value.trim() === "") {
    throw new Error(`Missing ${name}.`);
  }
  return value;
}

const evaluationSelect = [
  "id",
  "user_id",
  "updated_at",
  "fuel_price",
  "fuel_purchase_cost",
  "daily_customers",
  "average_litres",
  "monthly_rental",
  "monthly_staff_salary",
  "monthly_utilities",
  "monthly_maintenance",
  "monthly_other_cost",
  "initial_investment",
  "monthly_sales_volume",
  "monthly_revenue",
  "monthly_fuel_cost",
  "monthly_operating_cost",
  "monthly_profit",
  "profit_margin",
  "roi",
  "break_even_months",
  "profitability_score",
  "profitability_category",
  "recommendation",
  "explanation",
].join(",");

const insightSelect = [
  "evaluation_id",
  "insight",
  "model",
  "prompt_version",
  "input_hash",
  "source_evaluation_updated_at",
  "generated_at",
].join(",");
