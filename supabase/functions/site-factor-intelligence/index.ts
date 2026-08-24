import {
  createSiteFactorIntelligenceHandler,
  type SiteValidator,
  verifySupabaseAccessToken,
} from "./service.ts";

const supabaseUrl = requiredEnvironment("SUPABASE_URL");
const supabaseAnonKey = requiredEnvironment("SUPABASE_ANON_KEY");

Deno.serve(createSiteFactorIntelligenceHandler({
  authenticate: (accessToken) => verifySupabaseAccessToken(accessToken, {
    http: fetch, supabaseUrl, supabaseAnonKey,
  }),
  validator: createValidator(),
  http: fetch,
}));

function createValidator(): SiteValidator {
  return {
    async validate(candidate, accessToken) {
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), 5_000);
      try {
        const response = await fetch(`${supabaseUrl}/rest/v1/rpc/validate_east_malaysia_site`, {
          method: "POST",
          headers: {
            apikey: supabaseAnonKey, authorization: `Bearer ${accessToken}`,
            "content-type": "application/json",
          },
          body: JSON.stringify({
            p_latitude: candidate.latitude, p_longitude: candidate.longitude,
            p_analysis_radius_km: candidate.analysisRadiusKm,
          }),
          signal: controller.signal,
        });
        if (!response.ok) throw new Error("validator unavailable");
        const value = await response.json();
        if (!Array.isArray(value) || value.length !== 1 || value[0] === null ||
          typeof value[0] !== "object") throw new Error("validator returned an invalid result");
        const status = (value[0] as Record<string, unknown>).validation_status;
        if (typeof status !== "string") throw new Error("validator returned an invalid status");
        const confirmedTerritory = (value[0] as Record<string, unknown>).confirmed_territory;
        if (status !== "inside") {
          return { validationStatus: status, confirmedTerritory: null };
        }
        if (confirmedTerritory !== "sabah" && confirmedTerritory !== "sarawak" &&
          confirmedTerritory !== "labuan") {
          throw new Error("validator returned an invalid territory");
        }
        return { validationStatus: status, confirmedTerritory };
      } finally { clearTimeout(timeout); }
    },
  };
}
function requiredEnvironment(name: string): string {
  const value = Deno.env.get(name);
  if (value === undefined || value.trim() === "") throw new Error(`Missing ${name}.`);
  return value;
}
