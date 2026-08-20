import {
  parseCachedNearbyFuelStationsResult,
  toNearbyFuelStationsPublicResponse,
} from "./nearby_fuel_stations.ts";
import {
  createNearbyFuelStationsHandler,
  type FuelStationCache,
  type SiteValidator,
  verifySupabaseAccessToken,
} from "./service.ts";

const supabaseUrl = requiredEnvironment("SUPABASE_URL");
const supabaseAnonKey = requiredEnvironment("SUPABASE_ANON_KEY");
const supabaseServiceRoleKey = requiredEnvironment("SUPABASE_SERVICE_ROLE_KEY");

Deno.serve(createNearbyFuelStationsHandler({
  authenticate: (accessToken) => verifySupabaseAccessToken(accessToken, {
    http: fetch,
    supabaseUrl,
    supabaseAnonKey,
  }),
  validator: createValidator(),
  cache: createCache(),
  http: fetch,
}));

function createValidator(): SiteValidator {
  return {
    async validate(nearbyRequest, accessToken) {
      const response = await fetch(
        `${supabaseUrl}/rest/v1/rpc/validate_east_malaysia_site`,
        {
          method: "POST",
          headers: callerHeaders(accessToken),
          body: JSON.stringify({
            p_latitude: nearbyRequest.latitude,
            p_longitude: nearbyRequest.longitude,
            p_analysis_radius_km: nearbyRequest.analysisRadiusKm,
          }),
        },
      );
      if (!response.ok) throw new Error("validator unavailable");
      const value = await response.json();
      if (!Array.isArray(value) || value.length !== 1 ||
        value[0] === null || typeof value[0] !== "object") {
        throw new Error("validator returned an invalid result");
      }
      const status = (value[0] as Record<string, unknown>).validation_status;
      if (typeof status !== "string") {
        throw new Error("validator returned an invalid status");
      }
      return { validationStatus: status };
    },
  };
}

function createCache(): FuelStationCache {
  return {
    async get(nearbyRequest) {
      const response = await trustedRpc("nearby_fuel_station_cache_get", {
        p_latitude: nearbyRequest.latitude,
        p_longitude: nearbyRequest.longitude,
        p_analysis_radius_km: nearbyRequest.analysisRadiusKm,
      });
      if (!Array.isArray(response) || response.length === 0) return null;
      const cached = response[0];
      if (cached === null || typeof cached !== "object") return null;
      const cacheEntry = cached as Record<string, unknown>;
      return parseCachedNearbyFuelStationsResult(
        cacheEntry.cached_result,
        nearbyRequest,
        cacheEntry.fetched_at,
      );
    },
    async put(nearbyRequest, result, sourceResponse) {
      const response = await trustedRpc("nearby_fuel_station_cache_put", {
        p_latitude: nearbyRequest.latitude,
        p_longitude: nearbyRequest.longitude,
        p_analysis_radius_km: nearbyRequest.analysisRadiusKm,
        p_result: toNearbyFuelStationsPublicResponse(result),
        p_source_response: sourceResponse,
      });
      if (!Array.isArray(response) || response.length !== 1 ||
        response[0] === null || typeof response[0] !== "object") {
        throw new Error("cache returned an invalid result");
      }
      const cacheEntry = response[0] as Record<string, unknown>;
      return parseCachedNearbyFuelStationsResult(
        cacheEntry.cached_result,
        nearbyRequest,
        cacheEntry.fetched_at,
      );
    },
  };
}

async function trustedRpc(name: string, body: Record<string, unknown>): Promise<unknown> {
  const response = await fetch(`${supabaseUrl}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: {
      apikey: supabaseServiceRoleKey,
      authorization: `Bearer ${supabaseServiceRoleKey}`,
      "content-type": "application/json",
    },
    body: JSON.stringify(body),
  });
  if (!response.ok) throw new Error("cache unavailable");
  return response.json();
}

function callerHeaders(accessToken: string): HeadersInit {
  return {
    apikey: supabaseAnonKey,
    authorization: `Bearer ${accessToken}`,
    "content-type": "application/json",
  };
}

function requiredEnvironment(name: string): string {
  const value = Deno.env.get(name);
  if (value === undefined || value.trim() === "") {
    throw new Error(`Missing ${name}.`);
  }
  return value;
}
