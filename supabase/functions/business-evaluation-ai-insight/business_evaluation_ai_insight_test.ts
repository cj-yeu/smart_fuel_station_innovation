import {
  AiBusinessAdvisorUnavailable,
  businessEvaluationAiAdvisorModel,
  businessEvaluationAiAdvisorPromptVersion,
  createCanonicalBusinessEvaluationAdvisorInput,
  createOpenAiBusinessAdvisor,
  InvalidAiBusinessAdvisorInsight,
  InvalidAiBusinessAdvisorRequest,
  openAiResponsesEndpoint,
  parseAiBusinessAdvisorInsight,
  parseAiBusinessAdvisorRequestJson,
  sha256Hex,
} from "./business_evaluation_ai_insight.ts";
import {
  type AiBusinessAdvisorHandlerDependencies,
  type AiBusinessAdvisorRuntimeFailureLogEvent,
  type AiBusinessAdvisorRuntimeFailureStage,
  AuthenticationUnavailable,
  createAiBusinessAdvisorHandler,
  type StoredBusinessEvaluation,
  type StoredBusinessEvaluationAiInsight,
  verifySupabaseAccessToken,
} from "./service.ts";

const evaluationId = "11111111-1111-4111-8111-111111111111";
const otherEvaluationId = "22222222-2222-4222-8222-222222222222";
const userId = "33333333-3333-4333-8333-333333333333";
const updatedAt = "2026-08-31T00:00:00.000Z";

function assert(
  condition: unknown,
  message = "Assertion failed.",
): asserts condition {
  if (!condition) throw new Error(message);
}

function assertEquals<T>(actual: T, expected: T, message?: string): void {
  assert(
    JSON.stringify(actual) === JSON.stringify(expected),
    message ??
      `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}.`,
  );
}

async function assertRejects(
  callback: () => Promise<unknown>,
  type: new (...args: never[]) => Error,
): Promise<void> {
  try {
    await callback();
  } catch (error) {
    assert(error instanceof type, `Expected ${type.name}.`);
    return;
  }
  throw new Error(`Expected ${type.name}.`);
}

Deno.test("rejects malformed, duplicate, and extra public request fields", () => {
  assertThrowsRequest(() => parseAiBusinessAdvisorRequestJson("{}"));
  assertThrowsRequest(() =>
    parseAiBusinessAdvisorRequestJson(
      `{"evaluation_id":"${evaluationId}","extra":"no"}`,
    )
  );
  assertThrowsRequest(() =>
    parseAiBusinessAdvisorRequestJson(
      `{"evaluation_id":"${evaluationId}","evalu\\u0061tion_id":"${evaluationId}"}`,
    )
  );
  assertThrowsRequest(() =>
    parseAiBusinessAdvisorRequestJson(
      '{"evaluation_id":123}',
    )
  );
  assertThrowsRequest(() =>
    parseAiBusinessAdvisorRequestJson(
      `{"evaluation_id":"${otherEvaluationId}"} trailing`,
    )
  );
});

Deno.test("rejects an invalid evaluation UUID", () => {
  assertThrowsRequest(() =>
    parseAiBusinessAdvisorRequestJson(
      '{"evaluation_id":"not-a-uuid"}',
    )
  );
});

Deno.test("returns neutral 401 before any downstream call for missing or malformed auth", async () => {
  for (const authorization of [null, "Basic abc", "Bearer "]) {
    const fake = makeDependencies();
    const response = await createAiBusinessAdvisorHandler(fake.dependencies)(
      publicRequest(evaluationId, authorization),
    );
    assertEquals(response.status, 401);
    assertEquals(await response.json(), { error: "unauthorized" });
    assertEquals(fake.calls.read, 0);
    assertEquals(fake.calls.cacheGet, 0);
    assertEquals(fake.calls.advisor, 0);
  }
});

Deno.test("returns neutral 401 for an invalid or expired token without downstream calls", async () => {
  const fake = makeDependencies({ authenticate: () => Promise.resolve(false) });
  const response = await createAiBusinessAdvisorHandler(fake.dependencies)(
    publicRequest(evaluationId),
  );
  assertEquals(response.status, 401);
  assertEquals(await response.json(), { error: "unauthorized" });
  assertEquals(fake.calls.read, 0);
  assertEquals(fake.calls.cacheGet, 0);
  assertEquals(fake.calls.advisor, 0);
});

Deno.test("maps Auth transport failure to neutral 503 without downstream calls", async () => {
  const fake = makeDependencies({
    authenticate: () =>
      Promise.reject(new Error("provider response must stay private")),
  });
  const response = await createAiBusinessAdvisorHandler(fake.dependencies)(
    publicRequest(evaluationId),
  );
  assertEquals(response.status, 503);
  assertEquals(await response.json(), { error: "authentication_unavailable" });
  assertEquals(fake.calls.read, 0);
  assertEquals(fake.calls.cacheGet, 0);
  assertEquals(fake.calls.advisor, 0);
});

Deno.test("emits only safe fixed diagnostic events for each unavailable stage", async () => {
  const sensitiveValues = [
    "Bearer token-that-must-not-be-logged",
    evaluationId,
    "private@example.test",
    "5.9876,116.1234",
    "private provider response body",
    "1548750.00",
  ];
  const sensitiveError = new Error(sensitiveValues.join(" | "));
  const scenarios: Array<{
    stage: AiBusinessAdvisorRuntimeFailureStage;
    publicBody: Record<string, string>;
    overrides: TestDependencyOverrides;
  }> = [
    {
      stage: "auth_unavailable",
      publicBody: { error: "authentication_unavailable" },
      overrides: {
        authenticate: () => Promise.reject(sensitiveError),
      },
    },
    {
      stage: "evaluation_read_failed",
      publicBody: { error: "advisor_unavailable" },
      overrides: {
        readEvaluation: () => Promise.reject(sensitiveError),
      },
    },
    {
      stage: "insight_read_failed",
      publicBody: { error: "advisor_unavailable" },
      overrides: {
        readInsight: () => Promise.reject(sensitiveError),
      },
    },
    {
      stage: "provider_generation_failed",
      publicBody: { error: "advisor_unavailable" },
      overrides: {
        advisor: () => Promise.reject(sensitiveError),
      },
    },
    {
      stage: "insight_upsert_failed",
      publicBody: { error: "advisor_unavailable" },
      overrides: {
        upsertInsight: () => Promise.reject(sensitiveError),
      },
    },
  ];

  for (const scenario of scenarios) {
    const events: AiBusinessAdvisorRuntimeFailureLogEvent[] = [];
    const requestId = `request-${scenario.stage}`;
    const timestamps = [100, 125];
    const fake = makeDependencies({
      ...scenario.overrides,
      requestId: () => requestId,
      nowMilliseconds: () => timestamps.shift() ?? 125,
      logger: (event) => {
        events.push(event);
      },
    });
    const response = await createAiBusinessAdvisorHandler(fake.dependencies)(
      publicRequest(evaluationId, sensitiveValues[0]),
    );

    assertEquals(response.status, 503);
    assertEquals(await response.json(), scenario.publicBody);
    assertEquals(response.headers.get("x-ai-advisor-request-id"), requestId);
    assertEquals(events, [{
      event: "ai_advisor_runtime_failure",
      stage: scenario.stage,
      elapsed_ms: 25,
      request_id: requestId,
    }]);
    const serializedEvents = JSON.stringify(events);
    for (const sensitiveValue of sensitiveValues) {
      assert(!serializedEvents.includes(sensitiveValue));
    }
  }
});

Deno.test("does not emit failure events for generated or cached responses", async () => {
  const generatedEvents: AiBusinessAdvisorRuntimeFailureLogEvent[] = [];
  const generated = makeDependencies({
    requestId: () => "generated-request",
    logger: (event) => {
      generatedEvents.push(event);
    },
  });
  const generatedResponse = await createAiBusinessAdvisorHandler(
    generated.dependencies,
  )(publicRequest(evaluationId));
  assertEquals(generatedResponse.status, 200);
  assertEquals(
    generatedResponse.headers.get("x-ai-advisor-request-id"),
    "generated-request",
  );
  assertEquals(generatedEvents, []);

  const cachedEvents: AiBusinessAdvisorRuntimeFailureLogEvent[] = [];
  const cached = makeDependencies({
    cached: storedInsight(await sha256Hex(sampleEvaluation.advisorInput)),
    requestId: () => "cached-request",
    logger: (event) => {
      cachedEvents.push(event);
    },
  });
  const cachedResponse = await createAiBusinessAdvisorHandler(
    cached.dependencies,
  )(publicRequest(evaluationId));
  assertEquals(cachedResponse.status, 200);
  assertEquals(
    cachedResponse.headers.get("x-ai-advisor-request-id"),
    "cached-request",
  );
  assertEquals(cachedEvents, []);
});

Deno.test("classifies Auth invalid-token, network, 5xx, and invalid JSON responses safely", async () => {
  const common = {
    supabaseUrl: "https://project.supabase.co",
    supabaseAnonKey: "anon-key",
  };
  assertEquals(
    await verifySupabaseAccessToken("invalid", {
      ...common,
      http: () => Promise.resolve(new Response(null, { status: 401 })),
    }),
    false,
  );
  for (
    const http of [
      () => Promise.reject(new Error("network failure")),
      () => Promise.resolve(new Response("provider body", { status: 503 })),
      () => Promise.resolve(new Response("not-json", { status: 200 })),
    ]
  ) {
    await assertRejects(
      () => verifySupabaseAccessToken("token", { ...common, http }),
      AuthenticationUnavailable,
    );
  }
});

Deno.test("returns a neutral not-found response for an unauthorized or missing evaluation", async () => {
  const fake = makeDependencies({ evaluation: null });
  const response = await createAiBusinessAdvisorHandler(fake.dependencies)(
    publicRequest(evaluationId),
  );
  assertEquals(response.status, 404);
  assertEquals(await response.json(), { error: "evaluation_not_found" });
  assertEquals(fake.calls.cacheGet, 0);
  assertEquals(fake.calls.advisor, 0);
});

Deno.test("returns a cached owned evaluation insight without calling OpenAI", async () => {
  const inputHash = await sha256Hex(sampleEvaluation.advisorInput);
  const fake = makeDependencies({
    cached: storedInsight(inputHash),
  });
  const response = await createAiBusinessAdvisorHandler(fake.dependencies)(
    publicRequest(evaluationId),
  );
  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.cache_status, "cached");
  assertEquals(body.model, businessEvaluationAiAdvisorModel);
  assertEquals(fake.calls.advisor, 0);
  assertEquals(fake.calls.upsert, 0);
});

Deno.test("generates one advisory insight and writes only trusted metadata for a stale hash", async () => {
  const fake = makeDependencies({ cached: storedInsight("a".repeat(64)) });
  const response = await createAiBusinessAdvisorHandler(fake.dependencies)(
    publicRequest(evaluationId),
  );
  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.cache_status, "generated");
  assertEquals(fake.calls.advisor, 1);
  assertEquals(fake.calls.upsert, 1);
  assertEquals(fake.upserted?.evaluation.id, evaluationId);
  assertEquals(fake.upserted?.evaluation.userId, userId);
  assertEquals(
    fake.upserted?.inputHash,
    await sha256Hex(sampleEvaluation.advisorInput),
  );
  assertEquals(fake.upserted?.generatedAt, "2026-08-31T01:00:00.000Z");
});

Deno.test("returns a neutral unavailable error without leaking provider detail", async () => {
  const fake = makeDependencies({
    advisor: () => Promise.reject(new Error("internal provider response")),
  });
  const response = await createAiBusinessAdvisorHandler(fake.dependencies)(
    publicRequest(evaluationId),
  );
  const body = await response.text();
  assertEquals(response.status, 503);
  assertEquals(body, '{"error":"advisor_unavailable"}');
  assert(!body.includes("internal"));
  assert(!body.includes("provider"));
});

Deno.test("calls the exact fixed Responses endpoint, model, no-tools request, and strict schema", async () => {
  const callCapture: { url: string; init: RequestInit | null } = {
    url: "",
    init: null,
  };
  const advisor = createOpenAiBusinessAdvisor({
    apiKey: "test-key",
    http: (url, init) => {
      callCapture.url = url;
      callCapture.init = init;
      return Promise.resolve(jsonResponse({
        status: "completed",
        error: null,
        incomplete_details: null,
        output: [],
        output_text: JSON.stringify(sampleInsightRecord()),
      }));
    },
  });
  const insight = await advisor.create(sampleEvaluation.advisorInput);
  assertEquals(insight.actions.length, 3);
  assertEquals(callCapture.url, openAiResponsesEndpoint);
  const requestInit = callCapture.init;
  assert(requestInit !== null);
  assert(typeof requestInit.body === "string");
  const request = JSON.parse(requestInit.body) as Record<string, unknown>;
  assertEquals(request.model, "gpt-5.6-sol");
  assertEquals(request.store, false);
  assertEquals(request.reasoning, { effort: "low" });
  assertEquals(request.tools, []);
  assertEquals(request.tool_choice, "none");
  const format = (request.text as Record<string, unknown>).format as Record<
    string,
    unknown
  >;
  assertEquals(format.type, "json_schema");
  assertEquals(format.strict, true);
  assertEquals(
    (format.schema as Record<string, unknown>).additionalProperties,
    false,
  );
  assert(!String(request.input).includes(userId));
  assert(!String(request.input).includes("Module 3 AI Insight Test Station"));
});

Deno.test("handles timeout and non-200 OpenAI responses as neutral availability failures", async () => {
  const timeoutAdvisor = createOpenAiBusinessAdvisor({
    apiKey: "test-key",
    timeoutMs: 1,
    http: async (_url, init) =>
      await new Promise<Response>((_resolve, reject) => {
        (init.signal as AbortSignal).addEventListener(
          "abort",
          () => reject(new DOMException("Aborted", "AbortError")),
          { once: true },
        );
      }),
  });
  await assertRejects(
    () => timeoutAdvisor.create(sampleEvaluation.advisorInput),
    AiBusinessAdvisorUnavailable,
  );

  const rejectedAdvisor = createOpenAiBusinessAdvisor({
    apiKey: "test-key",
    http: () =>
      Promise.resolve(new Response("private provider error", { status: 429 })),
  });
  await assertRejects(
    () => rejectedAdvisor.create(sampleEvaluation.advisorInput),
    AiBusinessAdvisorUnavailable,
  );
});

Deno.test("rejects OpenAI refusal, incomplete, malformed, and oversized output", async () => {
  for (
    const payload of [
      {
        status: "incomplete",
        error: null,
        incomplete_details: { reason: "limit" },
        output: [],
        output_text: "{}",
      },
      {
        status: "completed",
        error: null,
        incomplete_details: null,
        output: [{ content: [{ type: "refusal" }] }],
        output_text: "{}",
      },
      {
        status: "completed",
        error: null,
        incomplete_details: null,
        output: [],
        output_text: "not json",
      },
      {
        status: "completed",
        error: null,
        incomplete_details: null,
        output: [],
        output_text: "x".repeat(32_769),
      },
    ]
  ) {
    const advisor = createOpenAiBusinessAdvisor({
      apiKey: "test-key",
      http: () => Promise.resolve(jsonResponse(payload)),
    });
    await assertRejects(
      () => advisor.create(sampleEvaluation.advisorInput),
      AiBusinessAdvisorUnavailable,
    );
  }
});

Deno.test("accepts only an exact bounded AI insight structure", () => {
  const insight = parseAiBusinessAdvisorInsight(sampleInsightRecord());
  assertEquals(insight.actions.length, 3);
  assertThrowsInsight(() =>
    parseAiBusinessAdvisorInsight({
      ...sampleInsightRecord(),
      extra: "no",
    })
  );
  assertThrowsInsight(() =>
    parseAiBusinessAdvisorInsight({
      ...sampleInsightRecord(),
      actions: sampleInsightRecord().actions.slice(0, 2),
    })
  );
});

const sampleEvaluation: StoredBusinessEvaluation = {
  id: evaluationId,
  userId,
  updatedAt,
  advisorInput: createCanonicalBusinessEvaluationAdvisorInput({
    fuelPrice: 2.95,
    fuelPurchaseCost: 2.2,
    dailyCustomers: 500,
    averageLitres: 35,
    monthlyRental: 20_000,
    monthlyStaffSalary: 30_000,
    monthlyUtilities: 5_000,
    monthlyMaintenance: 4_000,
    monthlyOtherCost: 2_000,
    initialInvestment: 2_000_000,
    monthlySalesVolume: 525_000,
    monthlyRevenue: 1_548_750,
    monthlyFuelCost: 1_155_000,
    monthlyOperatingCost: 1_216_000,
    monthlyProfit: 332_750,
    profitMargin: 21.49,
    roi: 199.65,
    breakEvenMonths: 6.01,
    profitabilityScore: 88.5,
    profitabilityCategory: "Profitable",
    recommendation:
      "The proposed fuel station shows strong financial potential.",
    explanation: "Deterministic calculation summary.",
  }),
};

type SampleInsightRecord = {
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
    variable: string;
    direction: string;
    reason: string;
  };
  data_limitations: string[];
  disclaimer: string;
};

function sampleInsightRecord(): SampleInsightRecord {
  return {
    executive_summary:
      "The supplied assumptions indicate a positive monthly profit.",
    drivers: [{
      type: "strength",
      factor: "Fuel margin",
      evidence:
        "The deterministic revenue and fuel-cost values show a positive margin.",
    }],
    actions: [
      {
        priority: "high",
        action: "Monitor demand",
        reason: "Daily customers are an input assumption.",
      },
      {
        priority: "medium",
        action: "Review costs",
        reason: "Fixed costs affect profit.",
      },
      {
        priority: "low",
        action: "Test sensitivity",
        reason: "Inputs can change.",
      },
    ],
    scenario_to_test: {
      variable: "daily_customers",
      direction: "review",
      reason: "Demand is an assumption.",
    },
    data_limitations: [
      "The advice uses only the supplied assumptions and deterministic results.",
    ],
    disclaimer:
      "This advisory output is for decision-support only and does not guarantee financial outcomes.",
  };
}

function storedInsight(inputHash: string): StoredBusinessEvaluationAiInsight {
  return {
    evaluationId,
    insight: parseAiBusinessAdvisorInsight(sampleInsightRecord()),
    model: businessEvaluationAiAdvisorModel,
    promptVersion: businessEvaluationAiAdvisorPromptVersion,
    inputHash,
    sourceEvaluationUpdatedAt: updatedAt,
    generatedAt: "2026-08-31T00:30:00.000Z",
  };
}

type TestDependencyOverrides = {
  authenticate?: () => Promise<boolean>;
  evaluation?: StoredBusinessEvaluation | null;
  cached?: StoredBusinessEvaluationAiInsight | null;
  readEvaluation?: () => Promise<StoredBusinessEvaluation | null>;
  readInsight?: () => Promise<StoredBusinessEvaluationAiInsight | null>;
  upsertInsight?: () => Promise<StoredBusinessEvaluationAiInsight>;
  advisor?: () => Promise<ReturnType<typeof parseAiBusinessAdvisorInsight>>;
  requestId?: () => string;
  nowMilliseconds?: () => number;
  logger?: (event: AiBusinessAdvisorRuntimeFailureLogEvent) => void;
};

function makeDependencies(overrides: TestDependencyOverrides = {}) {
  const calls = { read: 0, cacheGet: 0, advisor: 0, upsert: 0 };
  let upserted: {
    evaluation: StoredBusinessEvaluation;
    insight: ReturnType<typeof parseAiBusinessAdvisorInsight>;
    inputHash: string;
    generatedAt: string;
  } | null = null;
  const dependencies: AiBusinessAdvisorHandlerDependencies = {
    authenticate: overrides.authenticate ?? (() => Promise.resolve(true)),
    evaluationReader: {
      read() {
        calls.read += 1;
        if (overrides.readEvaluation !== undefined) {
          return overrides.readEvaluation();
        }
        return Promise.resolve(
          overrides.evaluation === undefined
            ? sampleEvaluation
            : overrides.evaluation,
        );
      },
    },
    insightStore: {
      get() {
        calls.cacheGet += 1;
        if (overrides.readInsight !== undefined) {
          return overrides.readInsight();
        }
        return Promise.resolve(overrides.cached ?? null);
      },
      upsert(value) {
        calls.upsert += 1;
        if (overrides.upsertInsight !== undefined) {
          return overrides.upsertInsight();
        }
        upserted = value;
        return Promise.resolve({
          evaluationId: value.evaluation.id,
          insight: value.insight,
          model: businessEvaluationAiAdvisorModel,
          promptVersion: businessEvaluationAiAdvisorPromptVersion,
          inputHash: value.inputHash,
          sourceEvaluationUpdatedAt: value.evaluation.updatedAt,
          generatedAt: value.generatedAt,
        });
      },
    },
    advisor: {
      async create() {
        calls.advisor += 1;
        return overrides.advisor === undefined
          ? parseAiBusinessAdvisorInsight(sampleInsightRecord())
          : await overrides.advisor();
      },
    },
    now: () => new Date("2026-08-31T01:00:00.000Z"),
    requestId: overrides.requestId,
    nowMilliseconds: overrides.nowMilliseconds,
    logger: overrides.logger ?? (() => {}),
  };
  return {
    dependencies,
    calls,
    get upserted() {
      return upserted;
    },
  };
}

function publicRequest(
  id: string,
  authorization: string | null = "Bearer valid-token",
): Request {
  const headers = new Headers({ "content-type": "application/json" });
  if (authorization !== null) headers.set("authorization", authorization);
  return new Request(
    "https://example.invalid/functions/v1/business-evaluation-ai-insight",
    {
      method: "POST",
      headers,
      body: JSON.stringify({ evaluation_id: id }),
    },
  );
}

function jsonResponse(value: unknown): Response {
  return new Response(JSON.stringify(value), {
    headers: { "content-type": "application/json" },
  });
}

function assertThrowsRequest(callback: () => unknown): void {
  try {
    callback();
  } catch (error) {
    assert(error instanceof InvalidAiBusinessAdvisorRequest);
    return;
  }
  throw new Error("Expected InvalidAiBusinessAdvisorRequest.");
}

function assertThrowsInsight(callback: () => unknown): void {
  try {
    callback();
  } catch (error) {
    assert(error instanceof InvalidAiBusinessAdvisorInsight);
    return;
  }
  throw new Error("Expected InvalidAiBusinessAdvisorInsight.");
}
