import {
  type CanonicalStationAssessmentExplanationInput,
  createCanonicalStationAssessmentExplanationInput,
  InvalidStationAssessmentAiExplanationRequest,
  InvalidStoredStationAssessment,
  OpenAiStationAssessmentExplanationFailure,
  parseBoundedStationAssessmentAiExplanationRequest,
} from "./station_assessment_ai_explanation.ts";
import {
  AuthenticationUnavailable,
  parseBearerToken,
} from "../_shared/supabase_auth.ts";

export type StoredStationAssessment = {
  id: string;
  userId: string;
  companyId: string;
  aiInput: CanonicalStationAssessmentExplanationInput;
};

export type AssessmentProfile = {
  userId: string;
  companyId: string;
  role: "company_user" | "company_admin";
};

export interface StationAssessmentReader {
  read(
    assessmentId: string,
    accessToken: string,
  ): Promise<StoredStationAssessment | null>;
}

export interface AssessmentProfileReader {
  read(accessToken: string): Promise<AssessmentProfile | null>;
}

export interface OpenAiStationAssessmentExplanation {
  create(input: CanonicalStationAssessmentExplanationInput): Promise<string>;
}

export type StationAssessmentAiExplanationFailureStage =
  | "auth_unavailable"
  | "assessment_read_failed"
  | "profile_read_failed"
  | "provider_generation_failed";

export type StationAssessmentAiExplanationFailureLogEvent = {
  event: "station_assessment_ai_explanation_failure";
  stage: StationAssessmentAiExplanationFailureStage;
  provider_failure_reason?: string;
  provider_http_status?: number;
  elapsed_ms: number;
  request_id: string;
};

export interface StationAssessmentAiExplanationHandlerDependencies {
  authenticate(accessToken: string): Promise<boolean>;
  assessmentReader: StationAssessmentReader;
  profileReader: AssessmentProfileReader;
  advisor: OpenAiStationAssessmentExplanation;
  nowMilliseconds?: () => number;
  requestId?: () => string;
  logger?: (event: StationAssessmentAiExplanationFailureLogEvent) => void;
}

class StationAssessmentUnavailable extends Error {}
class GenerationForbidden extends Error {}
class RuntimeFailure extends Error {
  readonly stage: StationAssessmentAiExplanationFailureStage;
  readonly providerFailure:
    | OpenAiStationAssessmentExplanationFailure
    | undefined;

  constructor(
    stage: StationAssessmentAiExplanationFailureStage,
    providerFailure?: OpenAiStationAssessmentExplanationFailure,
  ) {
    super("Station assessment AI explanation is unavailable.");
    this.stage = stage;
    this.providerFailure = providerFailure;
  }
}

export function createStationAssessmentAiExplanationHandler(
  dependencies: StationAssessmentAiExplanationHandlerDependencies,
): (request: Request) => Promise<Response> {
  return async (request) => {
    const requestId = (dependencies.requestId ?? (() => crypto.randomUUID()))();
    const nowMilliseconds = dependencies.nowMilliseconds ?? (() => Date.now());
    const startedAt = nowMilliseconds();
    const response = (
      value: unknown,
      status = 200,
      headers: HeadersInit = {},
    ) =>
      new Response(JSON.stringify(value), {
        status,
        headers: {
          "content-type": "application/json",
          "x-ai-advisor-request-id": requestId,
          ...headers,
        },
      });
    const logFailure = (failure: RuntimeFailure) => {
      const event: StationAssessmentAiExplanationFailureLogEvent = {
        event: "station_assessment_ai_explanation_failure",
        stage: failure.stage,
        ...(failure.providerFailure === undefined
          ? {}
          : { provider_failure_reason: failure.providerFailure.reason }),
        ...(failure.providerFailure?.httpStatus === undefined
          ? {}
          : { provider_http_status: failure.providerFailure.httpStatus }),
        elapsed_ms: Math.max(0, Math.round(nowMilliseconds() - startedAt)),
        request_id: requestId,
      };
      try {
        (dependencies.logger ?? defaultLogger)(event);
      } catch (_) {
        // Diagnostics must never change the neutral public response.
      }
    };

    if (request.method !== "POST") {
      return response({ error: "method_not_allowed" }, 405, { Allow: "POST" });
    }
    const accessToken = parseBearerToken(request.headers.get("authorization"));
    if (accessToken === null) return response({ error: "unauthorized" }, 401);

    try {
      if (!(await dependencies.authenticate(accessToken))) {
        return response({ error: "unauthorized" }, 401);
      }
    } catch (error) {
      if (!(error instanceof AuthenticationUnavailable)) {
        // All Auth transport failures remain neutral and diagnostic-only.
      }
      logFailure(new RuntimeFailure("auth_unavailable"));
      return response({ error: "authentication_unavailable" }, 503);
    }

    try {
      const parsedRequest =
        await parseBoundedStationAssessmentAiExplanationRequest(
          request,
        );
      const explanation = await generateStationAssessmentAiExplanation(
        parsedRequest.assessmentId,
        accessToken,
        dependencies,
      );
      return response({ explanation });
    } catch (error) {
      if (error instanceof InvalidStationAssessmentAiExplanationRequest) {
        return response({ error: "invalid_request" }, 400);
      }
      if (error instanceof StationAssessmentUnavailable) {
        return response({ error: "assessment_not_found" }, 404);
      }
      if (error instanceof GenerationForbidden) {
        return response({ error: "forbidden" }, 403);
      }
      if (error instanceof RuntimeFailure) logFailure(error);
      return response({ error: "advisor_unavailable" }, 503);
    }
  };
}

export async function generateStationAssessmentAiExplanation(
  assessmentId: string,
  accessToken: string,
  dependencies: StationAssessmentAiExplanationHandlerDependencies,
): Promise<string> {
  let assessment: StoredStationAssessment | null;
  try {
    assessment = await dependencies.assessmentReader.read(
      assessmentId,
      accessToken,
    );
  } catch (_) {
    throw new RuntimeFailure("assessment_read_failed");
  }
  if (assessment === null) throw new StationAssessmentUnavailable();

  let profile: AssessmentProfile | null;
  try {
    profile = await dependencies.profileReader.read(accessToken);
  } catch (_) {
    throw new RuntimeFailure("profile_read_failed");
  }
  if (profile === null) throw new GenerationForbidden();
  if (
    profile.companyId !== assessment.companyId ||
    (profile.userId !== assessment.userId && profile.role !== "company_admin")
  ) {
    throw new GenerationForbidden();
  }

  try {
    return await dependencies.advisor.create(assessment.aiInput);
  } catch (error) {
    throw new RuntimeFailure(
      "provider_generation_failed",
      error instanceof OpenAiStationAssessmentExplanationFailure
        ? error
        : undefined,
    );
  }
}

export function parseStoredStationAssessment(
  value: unknown,
): StoredStationAssessment {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new InvalidStoredStationAssessment();
  }
  const row = value as Record<string, unknown>;
  const companyId = parseStoredUuid(row.company_id);
  return {
    id: parseStoredUuid(row.id),
    userId: parseStoredUuid(row.user_id),
    companyId,
    aiInput: createCanonicalStationAssessmentExplanationInput({
      populationDensity: row.population_density,
      trafficLevel: row.traffic_level,
      registeredVehicleCount: row.registered_vehicle_count,
      nearbyFuelStations: row.nearby_fuel_stations,
      competitorDistanceKm: row.competitor_distance_km,
      roadAccessibility: row.road_accessibility,
      commercialActivity: row.commercial_activity,
      residentialActivity: row.residential_activity,
      landAccessibility: row.land_accessibility,
      finalScore: row.final_score,
      suitabilityCategory: row.suitability_category,
      geographicValidationStatus: row.geographic_validation_status,
      confirmedTerritory: row.confirmed_territory,
    }),
  };
}

export function parseAssessmentProfile(value: unknown): AssessmentProfile {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new InvalidStoredStationAssessment();
  }
  const row = value as Record<string, unknown>;
  const role = row.role;
  if (role !== "company_user" && role !== "company_admin") {
    throw new InvalidStoredStationAssessment();
  }
  return {
    userId: parseStoredUuid(row.user_id),
    companyId: parseStoredUuid(row.company_id),
    role,
  };
}

function parseStoredUuid(value: unknown): string {
  if (
    typeof value !== "string" ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(value)
  ) {
    throw new InvalidStoredStationAssessment();
  }
  return value.toLowerCase();
}

function defaultLogger(
  event: StationAssessmentAiExplanationFailureLogEvent,
): void {
  console.log(JSON.stringify(event));
}
