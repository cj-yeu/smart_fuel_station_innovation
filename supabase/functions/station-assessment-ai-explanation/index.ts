import {
  createOpenAiStationAssessmentExplanation,
} from "./station_assessment_ai_explanation.ts";
import {
  createStationAssessmentAiExplanationHandler,
  parseAssessmentProfile,
  parseStoredStationAssessment,
} from "./service.ts";
import { verifySupabaseAccessToken } from "../_shared/supabase_auth.ts";

const supabaseUrl = requiredEnvironment("SUPABASE_URL");
const supabaseAnonKey = requiredEnvironment("SUPABASE_ANON_KEY");
const openAiApiKey = requiredEnvironment("OPENAI_API_KEY");

Deno.serve(createStationAssessmentAiExplanationHandler({
  authenticate: (accessToken) =>
    verifySupabaseAccessToken(accessToken, {
      http: fetch,
      supabaseUrl,
      supabaseAnonKey,
    }),
  assessmentReader: {
    async read(assessmentId, accessToken) {
      const response = await fetch(
        `${supabaseUrl}/rest/v1/station_assessments?select=${
          encodeURIComponent(assessmentSelect)
        }&id=eq.${encodeURIComponent(assessmentId)}&limit=2`,
        { headers: callerHeaders(accessToken) },
      );
      if (!response.ok) throw new Error("assessment unavailable");
      const rows = await response.json();
      if (!Array.isArray(rows)) throw new Error("assessment response invalid");
      if (rows.length === 0) return null;
      if (rows.length !== 1) throw new Error("assessment response ambiguous");
      return parseStoredStationAssessment(rows[0]);
    },
  },
  profileReader: {
    async read(accessToken) {
      const response = await fetch(
        `${supabaseUrl}/rest/v1/profiles?select=user_id,company_id,role&limit=2`,
        { headers: callerHeaders(accessToken) },
      );
      if (!response.ok) throw new Error("profile unavailable");
      const rows = await response.json();
      if (!Array.isArray(rows)) throw new Error("profile response invalid");
      if (rows.length === 0) return null;
      if (rows.length !== 1) throw new Error("profile response ambiguous");
      return parseAssessmentProfile(rows[0]);
    },
  },
  advisor: createOpenAiStationAssessmentExplanation({
    http: fetch,
    apiKey: openAiApiKey,
  }),
}));

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

const assessmentSelect = [
  "id",
  "user_id",
  "company_id",
  "population_density",
  "traffic_level",
  "registered_vehicle_count",
  "nearby_fuel_stations",
  "competitor_distance_km",
  "road_accessibility",
  "commercial_activity",
  "residential_activity",
  "land_accessibility",
  "final_score",
  "suitability_category",
  "geographic_validation_status",
  "confirmed_territory",
].join(",");
