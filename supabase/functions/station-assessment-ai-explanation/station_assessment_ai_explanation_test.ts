import {
  buildOpenAiStationAssessmentExplanationRequest,
  createCanonicalStationAssessmentExplanationInput,
  createOpenAiStationAssessmentExplanation,
  InvalidStationAssessmentAiExplanationRequest,
  parseStationAssessmentAiExplanationRequestJson,
  stationAssessmentAiExplanationModel,
} from "./station_assessment_ai_explanation.ts";
import {
  createStationAssessmentAiExplanationHandler,
  parseStoredStationAssessment,
  type StationAssessmentAiExplanationHandlerDependencies,
} from "./service.ts";

const assessmentId = "11111111-1111-4111-8111-111111111111";
const creatorId = "22222222-2222-4222-8222-222222222222";
const adminId = "33333333-3333-4333-8333-333333333333";
const otherId = "44444444-4444-4444-8444-444444444444";
const companyId = "55555555-5555-4555-8555-555555555555";

function assert(
  condition: unknown,
  message = "Assertion failed.",
): asserts condition {
  if (!condition) throw new Error(message);
}

function assertEquals<T>(actual: T, expected: T): void {
  assert(JSON.stringify(actual) === JSON.stringify(expected));
}

Deno.test("rejects unsupported methods and exact-invalid request shapes", async () => {
  const handler = createStationAssessmentAiExplanationHandler(dependencies());

  const methodResponse = await handler(
    new Request("https://example.invalid", { method: "GET" }),
  );
  assertEquals(methodResponse.status, 405);
  assertEquals(methodResponse.headers.get("allow"), "POST");

  for (
    const raw of [
      "{}",
      `{"assessment_id":"${assessmentId}","extra":"x"}`,
      `{"assessment_id":"${assessmentId}","assess\\u006dent_id":"${assessmentId}"}`,
      '{"assessment_id":123}',
      '{"assessment_id":"not-a-uuid"}',
    ]
  ) {
    try {
      parseStationAssessmentAiExplanationRequestJson(raw);
      throw new Error("Expected invalid request.");
    } catch (error) {
      assert(error instanceof InvalidStationAssessmentAiExplanationRequest);
    }
  }
});

Deno.test("requires valid authentication before any assessment read", async () => {
  let assessmentReads = 0;
  const handler = createStationAssessmentAiExplanationHandler(dependencies({
    authenticate: () => Promise.resolve(false),
    assessmentReader: {
      read: () => {
        assessmentReads += 1;
        return Promise.resolve(sampleAssessment());
      },
    },
  }));

  const missing = await handler(postRequest());
  const invalid = await handler(postRequest("Bearer invalid"));
  assertEquals(missing.status, 401);
  assertEquals(invalid.status, 401);
  assertEquals(assessmentReads, 0);
});

Deno.test("reads the assessment and profile with the caller JWT", async () => {
  const tokens: string[] = [];
  const handler = createStationAssessmentAiExplanationHandler(dependencies({
    assessmentReader: {
      read: (_, token) => {
        tokens.push(token);
        return Promise.resolve(sampleAssessment());
      },
    },
    profileReader: {
      read: (token) => {
        tokens.push(token);
        return Promise.resolve(creatorProfile());
      },
    },
  }));

  const response = await handler(postRequest("Bearer caller-token"));
  assertEquals(response.status, 200);
  assertEquals(tokens, ["caller-token", "caller-token"]);
});

Deno.test("returns a neutral result for missing or cross-company assessments", async () => {
  const handler = createStationAssessmentAiExplanationHandler(dependencies({
    assessmentReader: { read: () => Promise.resolve(null) },
  }));
  const response = await handler(postRequest());
  assertEquals(response.status, 404);
  assertEquals(await response.json(), { error: "assessment_not_found" });

  const crossCompanyHandler = createStationAssessmentAiExplanationHandler(
    dependencies({
      profileReader: {
        read: () =>
          Promise.resolve({
            ...creatorProfile(),
            companyId: "66666666-6666-4666-8666-666666666666",
          }),
      },
    }),
  );
  const crossCompanyResponse = await crossCompanyHandler(postRequest());
  assertEquals(crossCompanyResponse.status, 403);
  assertEquals(await crossCompanyResponse.json(), { error: "forbidden" });
});

Deno.test("allows the creator and a same-company admin but denies a company user", async () => {
  const createdBy = (profile: {
    userId: string;
    companyId: string;
    role: "company_user" | "company_admin";
  }) => {
    const handler = createStationAssessmentAiExplanationHandler(dependencies({
      profileReader: { read: () => Promise.resolve(profile) },
    }));
    return handler(postRequest());
  };

  assertEquals((await createdBy(creatorProfile())).status, 200);
  assertEquals((await createdBy(adminProfile())).status, 200);
  const denied = await createdBy({
    ...creatorProfile(),
    userId: otherId,
    role: "company_user",
  });
  assertEquals(denied.status, 403);
  assertEquals(await denied.json(), { error: "forbidden" });
});

Deno.test("server canonical input excludes text and identity fields", () => {
  const assessment = parseStoredStationAssessment({
    ...storedAssessmentRow(),
    location_name: "Untrusted Station Name",
    recommendation: "Do not send",
    explanation: "Do not send",
    site_location: "not selected",
  });
  const request = buildOpenAiStationAssessmentExplanationRequest(
    assessment.aiInput,
  );
  const input = JSON.stringify(request.input);

  assert(!input.includes("Untrusted Station Name"));
  assert(!input.includes(assessmentId));
  assert(!input.includes(companyId));
  assert(!input.includes("Do not send"));
  assertEquals(request.model, stationAssessmentAiExplanationModel);
  assertEquals(request.store, false);
});

Deno.test("only an inside assessment includes its confirmed territory", () => {
  const inside = createCanonicalStationAssessmentExplanationInput(
    canonicalValues(),
  );
  const legacy = createCanonicalStationAssessmentExplanationInput({
    ...canonicalValues(),
    geographicValidationStatus: "legacy_unverified",
    confirmedTerritory: "sabah",
  });
  assertEquals(inside.geography.confirmed_territory, "sabah");
  assertEquals(legacy.geography.confirmed_territory, null);
});

Deno.test("uses the completed assistant output and rejects a provider refusal safely", async () => {
  const provider = createOpenAiStationAssessmentExplanation({
    apiKey: "sentinel-secret",
    http: () =>
      Promise.resolve(
        new Response(JSON.stringify(completedResponse()), { status: 200 }),
      ),
  });
  const explanation = await provider.create(
    createCanonicalStationAssessmentExplanationInput(canonicalValues()),
  );
  assertEquals(
    explanation,
    "Traffic and accessibility support the deterministic result.",
  );

  const refusalProvider = createOpenAiStationAssessmentExplanation({
    apiKey: "sentinel-secret",
    http: () =>
      Promise.resolve(
        new Response(
          JSON.stringify({
            status: "completed",
            error: null,
            incomplete_details: null,
            output: [{
              type: "message",
              role: "assistant",
              status: "completed",
              content: [{ type: "refusal" }],
            }],
          }),
          { status: 200 },
        ),
      ),
  });
  await assertRejects(() =>
    refusalProvider.create(
      createCanonicalStationAssessmentExplanationInput(canonicalValues()),
    )
  );
});

Deno.test("classifies a provider timeout without exposing provider detail", async () => {
  const provider = createOpenAiStationAssessmentExplanation({
    apiKey: "sentinel-secret",
    timeoutMs: 1,
    http: (_, init) =>
      new Promise<Response>((_, reject) => {
        const signal = init.signal;
        if (signal === null || signal === undefined) {
          reject(new Error("Expected an abort signal."));
          return;
        }
        signal.addEventListener(
          "abort",
          () => reject(new DOMException("Aborted", "AbortError")),
          { once: true },
        );
      }),
  });

  await assertRejects(() =>
    provider.create(
      createCanonicalStationAssessmentExplanationInput(canonicalValues()),
    )
  );
});

Deno.test("maps provider failure to a neutral response and logs fixed data only", async () => {
  const events: Record<string, unknown>[] = [];
  const handler = createStationAssessmentAiExplanationHandler(dependencies({
    advisor: { create: () => Promise.reject(new Error("secret token 123")) },
    logger: (event) => events.push(event),
  }));
  const response = await handler(postRequest());

  assertEquals(response.status, 503);
  assertEquals(await response.json(), { error: "advisor_unavailable" });
  assertEquals(events.length, 1);
  assertEquals(events[0].stage, "provider_generation_failed");
  const logged = JSON.stringify(events[0]);
  for (
    const secret of [
      "secret token",
      assessmentId,
      companyId,
      "Traffic and accessibility",
    ]
  ) {
    assert(!logged.includes(secret));
  }
  assert(response.headers.get("x-ai-advisor-request-id") !== null);
});

function dependencies(
  overrides: Partial<StationAssessmentAiExplanationHandlerDependencies> = {},
): StationAssessmentAiExplanationHandlerDependencies {
  return {
    authenticate: () => Promise.resolve(true),
    assessmentReader: { read: () => Promise.resolve(sampleAssessment()) },
    profileReader: { read: () => Promise.resolve(creatorProfile()) },
    advisor: {
      create: () =>
        Promise.resolve(
          "Traffic and accessibility support the deterministic result.",
        ),
    },
    requestId: () => "safe-request-id",
    nowMilliseconds: () => 100,
    ...overrides,
  };
}

function postRequest(authorization = "Bearer caller-token"): Request {
  return new Request("https://example.invalid", {
    method: "POST",
    headers: {
      authorization,
      "content-type": "application/json",
    },
    body: JSON.stringify({ assessment_id: assessmentId }),
  });
}

function sampleAssessment() {
  return parseStoredStationAssessment(storedAssessmentRow());
}

function storedAssessmentRow() {
  return {
    id: assessmentId,
    user_id: creatorId,
    company_id: companyId,
    population_density: 2000,
    traffic_level: 4,
    registered_vehicle_count: 10000,
    nearby_fuel_stations: 2,
    competitor_distance_km: 3.5,
    road_accessibility: 4,
    commercial_activity: 3,
    residential_activity: 3,
    land_accessibility: 4,
    final_score: 72.5,
    suitability_category: "Good",
    geographic_validation_status: "inside",
    confirmed_territory: "sabah",
  };
}

function canonicalValues() {
  return {
    populationDensity: 2000,
    trafficLevel: 4,
    registeredVehicleCount: 10000,
    nearbyFuelStations: 2,
    competitorDistanceKm: 3.5,
    roadAccessibility: 4,
    commercialActivity: 3,
    residentialActivity: 3,
    landAccessibility: 4,
    finalScore: 72.5,
    suitabilityCategory: "Good",
    geographicValidationStatus: "inside",
    confirmedTerritory: "sabah",
  };
}

function creatorProfile() {
  return { userId: creatorId, companyId, role: "company_user" as const };
}

function adminProfile() {
  return { userId: adminId, companyId, role: "company_admin" as const };
}

function completedResponse() {
  return {
    status: "completed",
    error: null,
    incomplete_details: null,
    output: [{ type: "reasoning" }, {
      type: "message",
      role: "assistant",
      status: "completed",
      content: [{
        type: "output_text",
        text: JSON.stringify({
          explanation:
            "Traffic and accessibility support the deterministic result.",
        }),
      }],
    }],
  };
}

async function assertRejects(callback: () => Promise<unknown>): Promise<void> {
  try {
    await callback();
  } catch (_) {
    return;
  }
  throw new Error("Expected rejection.");
}
