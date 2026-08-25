import {
  InvalidNearbyFuelStationsRequest,
  UpstreamFuelStationsFailure,
  buildFixedOverpassQuery,
  fallbackOverpassEndpoint,
  haversineDistanceKm,
  maximumOverpassResponseBytes,
  maximumRequestBodyBytes,
  maximumReturnedStationCount,
  maximumUpstreamElementCount,
  openStreetMapAttribution,
  openStreetMapAttributionUrl,
  overpassEndpoint,
  parseCachedNearbyFuelStationsResult,
  parseBearerToken,
  parseBoundedNearbyFuelStationsRequestBody,
  parseNearbyFuelStationsRequest,
  parseNearbyFuelStationsRequestJson,
  parseOverpassFuelStations,
  toNearbyFuelStationsPublicResponse,
  validateNearbyFuelStationsRequest,
} from "./nearby_fuel_stations.ts";
import {
  AuthenticationUnavailable,
  SiteNotValidatedInside,
  createNearbyFuelStationsHandler,
  fetchFixedOverpassPayload,
  loadNearbyFuelStations,
  overpassUserAgent,
  verifySupabaseAccessToken,
} from "./service.ts";

const request = validateNearbyFuelStationsRequest({
  latitude: 5.9804,
  longitude: 116.0735,
  analysisRadiusKm: 5,
});

function assert(condition: unknown, message = "Assertion failed."): asserts condition {
  if (!condition) throw new Error(message);
}

function assertEquals<T>(actual: T, expected: T, message?: string): void {
  assert(
    JSON.stringify(actual) === JSON.stringify(expected),
    message ?? `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}.`,
  );
}

function assertThrows(
  callback: () => unknown,
  type: new (...args: never[]) => Error,
): void {
  try {
    callback();
  } catch (error) {
    assert(error instanceof type, `Expected ${type.name}.`);
    return;
  }
  throw new Error(`Expected ${type.name}.`);
}

Deno.test("parses node coordinates and preserves allowed OSM tags", () => {
  const [station] = parseOverpassFuelStations({
    elements: [{
      type: "node",
      id: 42,
      lat: 5.981,
      lon: 116.074,
      tags: { name: "Example Fuel", brand: "Example", operator: "Operator" },
    }],
  }, request);

  assertEquals(station.osmType, "node");
  assertEquals(station.osmId, "42");
  assertEquals(station.name, "Example Fuel");
  assertEquals(station.brand, "Example");
  assertEquals(station.operator, "Operator");
  assert(Number.isFinite(station.distanceKm));
});

Deno.test("parses way and relation centres", () => {
  const stations = parseOverpassFuelStations({
    elements: [
      { type: "way", id: 2, center: { lat: 5.982, lon: 116.075 } },
      { type: "relation", id: 3, center: { lat: 5.983, lon: 116.076 } },
    ],
  }, request);

  assertEquals(stations.map((station) => station.osmType).sort(), [
    "relation",
    "way",
  ]);
});

Deno.test("uses null for missing name brand and operator", () => {
  const [station] = parseOverpassFuelStations({
    elements: [{ type: "node", id: 4, lat: 5.981, lon: 116.074 }],
  }, request);
  assertEquals([station.name, station.brand, station.operator], [null, null, null]);
});

Deno.test("ignores malformed, non-finite, and out-of-range upstream elements", () => {
  const stations = parseOverpassFuelStations({
    elements: [
      { type: "node", id: 1, lat: Number.POSITIVE_INFINITY, lon: 116 },
      { type: "node", id: 2, lat: -91, lon: 116 },
      { type: "way", id: 3, center: { lat: 5, lon: 181 } },
      { type: "relation", id: "not-an-id", center: { lat: 5, lon: 116 } },
      { type: "node", id: 5, lat: 5, lon: 116 },
    ],
  }, request);
  assertEquals(stations.map((station) => station.osmId), ["5"]);
});

Deno.test("deduplicates identity and sorts by distance type then ID", () => {
  const stations = parseOverpassFuelStations({
    elements: [
      { type: "way", id: 9, center: { lat: 5.9804, lon: 116.0735 } },
      { type: "node", id: 2, lat: 5.9804, lon: 116.0735 },
      { type: "node", id: 2, lat: 5.9804, lon: 116.0735 },
      { type: "node", id: 1, lat: 5.9804, lon: 116.0735 },
    ],
  }, request);
  assertEquals(stations.map((station) => `${station.osmType}:${station.osmId}`), [
    "node:1",
    "node:2",
    "way:9",
  ]);
});

Deno.test("validates only finite East Malaysia candidate input and 3 5 10 km", () => {
  for (const radius of [3, 5, 10]) {
    assertEquals(
      validateNearbyFuelStationsRequest({
        latitude: 5,
        longitude: 116,
        analysisRadiusKm: radius,
      }).analysisRadiusKm,
      radius,
    );
  }
  assertThrows(
    () => validateNearbyFuelStationsRequest({ latitude: Number.NaN, longitude: 116, analysisRadiusKm: 5 }),
    InvalidNearbyFuelStationsRequest,
  );
  assertThrows(
    () => validateNearbyFuelStationsRequest({ latitude: 5, longitude: 116, analysisRadiusKm: 4 }),
    InvalidNearbyFuelStationsRequest,
  );
  assertThrows(
    () => validateNearbyFuelStationsRequest({ latitude: 5, longitude: 116, analysisRadiusKm: 5.5 }),
    InvalidNearbyFuelStationsRequest,
  );
});

Deno.test("caps result output and rejects oversized upstream arrays", () => {
  const elements = Array.from({ length: 8 }, (_, index) => ({
    type: "node",
    id: index + 1,
    lat: 5.98 + index / 100,
    lon: 116.07,
  }));
  assertEquals(parseOverpassFuelStations({ elements }, request, 3).length, 3);
  assertThrows(
    () => parseOverpassFuelStations(
      { elements: Array.from({ length: maximumUpstreamElementCount + 1 }, () => ({})) },
      request,
    ),
    UpstreamFuelStationsFailure,
  );
});

Deno.test("uses a fixed amenity=fuel query and exact attribution", () => {
  const query = buildFixedOverpassQuery(request);
  assert(query.includes('["amenity"="fuel"]'));
  assert(query.includes("out center tags;"));
  assertEquals(openStreetMapAttribution, "© OpenStreetMap contributors");
  assertEquals(openStreetMapAttributionUrl, "https://www.openstreetmap.org/copyright");
});

Deno.test("rejects client-controlled Overpass endpoint and query fields", () => {
  assertThrows(
    () => parseNearbyFuelStationsRequest({
      latitude: 5,
      longitude: 116,
      analysis_radius_km: 5,
      overpass_url: "https://untrusted.example",
    }),
    InvalidNearbyFuelStationsRequest,
  );
  assertThrows(
    () => parseNearbyFuelStationsRequest({
      latitude: 5,
      longitude: 116,
      analysis_radius_km: 5,
      query: "nwr(…)",
    }),
    InvalidNearbyFuelStationsRequest,
  );
});

Deno.test("maps timeout and upstream failure without a network call", async () => {
  await assertRejects(
    () => fetchFixedOverpassPayload(
      async () => {
        throw new DOMException("aborted", "AbortError");
      },
      request,
    ),
    UpstreamFuelStationsFailure,
  );
});

Deno.test("uses the fixed fallback only after the primary endpoint fails", async () => {
  const requestedUrls: string[] = [];
  const payload = await fetchFixedOverpassPayload(async (url) => {
    requestedUrls.push(url);
    return requestedUrls.length == 1
      ? new Response("", { status: 503 })
      : new Response('{"elements":[]}');
  }, request);

  assertEquals(payload, { elements: [] });
  assertEquals(requestedUrls, [overpassEndpoint, fallbackOverpassEndpoint]);
});

Deno.test("uses injected validator cache and HTTP without own competitor inference", async () => {
  let httpCalls = 0;
  const result = await loadNearbyFuelStations(request, "test.jwt", {
    validator: { validate: async () => ({ validationStatus: "inside" }) },
    cache: {
      get: async () => null,
      put: async (_request, value, _sourceResponse) => value,
    },
    http: async () => {
      httpCalls += 1;
      return new Response(JSON.stringify({
        elements: [{
          type: "node",
          id: 12,
          lat: 5.9805,
          lon: 116.0736,
          tags: { brand: "Unrelated Brand" },
        }],
      }), { status: 200 });
    },
    now: () => new Date("2026-08-20T00:00:00.000Z"),
  });
  assertEquals(httpCalls, 1);
  assertEquals(result.stationCount, 1);
  assert(!("company_id" in result.stations[0]));
  assert(!("ownership" in result.stations[0]));
  assert(!("competitor" in result.stations[0]));
});

Deno.test("fails closed when the authoritative validator is not inside", async () => {
  await assertRejects(
    () => loadNearbyFuelStations(request, "test.jwt", {
      validator: { validate: async () => ({ validationStatus: "unverified" }) },
      cache: {
        get: async () => null,
        put: async (_request, value, _sourceResponse) => value,
      },
      http: async () => {
        throw new Error("must not call upstream");
      },
    }),
    SiteNotValidatedInside,
  );
});

Deno.test("rejects duplicate, ambiguous, and non-numeric raw request values", async () => {
  for (const duplicate of [
    '{"latitude":5,"latitude":6,"longitude":116,"analysis_radius_km":5}',
    '{"latitude":5,"longitude":116,"longitude":117,"analysis_radius_km":5}',
    '{"latitude":5,"longitude":116,"analysis_radius_km":5,"analysis_radius_km":3}',
  ]) {
    assertThrows(
      () => parseNearbyFuelStationsRequestJson(duplicate),
      InvalidNearbyFuelStationsRequest,
    );
  }

  for (const raw of [
    '{"latitude":"5","longitude":116,"analysis_radius_km":5}',
    '{"latitude":null,"longitude":116,"analysis_radius_km":5}',
    '{"latitude":true,"longitude":116,"analysis_radius_km":5}',
    '{"latitude":[],"longitude":116,"analysis_radius_km":5}',
    '{"latitude":{},"longitude":116,"analysis_radius_km":5}',
    '{"latitude":5,"longitude":116}',
    '{"latitude":5,"longitude":116,"analysis_radius_km":5,"extra":1}',
    '{"lat\\qitude":5,"longitude":116,"analysis_radius_km":5}',
    '{"latitude":5,"longitude":116,"analysis_radius_km":5} trailing',
  ]) {
    assertThrows(
      () => parseNearbyFuelStationsRequestJson(raw),
      InvalidNearbyFuelStationsRequest,
    );
  }

  const exact = parseNearbyFuelStationsRequestJson(
    '{"latitude":5.980400123,"longitude":116.073500987,"analysis_radius_km":5}',
  );
  assertEquals(exact.latitude, 5.980400123);
  assertEquals(exact.longitude, 116.073500987);
});

Deno.test("cancels declared and streamed oversized request bodies", async () => {
  const declared = trackedBytesStream(
    '{"latitude":5,"longitude":116,"analysis_radius_km":5}',
  );
  await assertRejects(
    () => parseBoundedNearbyFuelStationsRequestBody(
      declared.stream,
      String(maximumRequestBodyBytes + 1),
    ),
    InvalidNearbyFuelStationsRequest,
  );
  assertEquals(declared.cancellationCount(), 1);

  const streamed = trackedBytesStream(
    new Uint8Array(maximumRequestBodyBytes + 1),
  );
  await assertRejects(
    () => parseBoundedNearbyFuelStationsRequestBody(
      streamed.stream,
      "1",
    ),
    InvalidNearbyFuelStationsRequest,
  );
  assertEquals(streamed.cancellationCount(), 1);

  await assertRejects(
    () => parseBoundedNearbyFuelStationsRequestBody(
      bytesStream(new Uint8Array([0xff])),
      null,
    ),
    InvalidNearbyFuelStationsRequest,
  );
});

Deno.test("preserves exact coordinates, normalizes only negative zero, and keeps order", () => {
  const exact = validateNearbyFuelStationsRequest({
    latitude: 5.980400123,
    longitude: 116.073500987,
    analysisRadiusKm: 10,
  });
  assertEquals(exact.latitude, 5.980400123);
  assertEquals(exact.longitude, 116.073500987);
  assert(buildFixedOverpassQuery(exact).includes("10000,5.980400123,116.073500987"));

  const negativeZero = validateNearbyFuelStationsRequest({
    latitude: -0,
    longitude: -0,
    analysisRadiusKm: 3,
  });
  assert(Object.is(negativeZero.latitude, 0));
  assert(Object.is(negativeZero.longitude, 0));
});

Deno.test("rejects missing or invalid authorization syntax without trusting a token", () => {
  assertEquals(parseBearerToken(null), null);
  assertEquals(parseBearerToken("Basic credentials"), null);
  assertEquals(parseBearerToken("Bearer   "), null);
  assertEquals(parseBearerToken("Bearer verified.by.supabase"), "verified.by.supabase");
});

Deno.test("maps Supabase Auth invalid tokens and transport failures safely", async () => {
  const authenticationDependencies = {
    supabaseUrl: "https://project.example",
    supabaseAnonKey: "public-anon-key",
  };
  assertEquals(
    await verifySupabaseAccessToken("expired.jwt", {
      ...authenticationDependencies,
      http: async () => new Response("{}", { status: 401 }),
    }),
    false,
  );

  for (const http of [
    async () => {
      throw new TypeError("network unavailable");
    },
    async () => new Response("provider failure", { status: 503 }),
    async () => new Response("not-json", { status: 200 }),
  ]) {
    await assertRejects(
      () => verifySupabaseAccessToken("test.jwt", {
        ...authenticationDependencies,
        http,
      }),
      AuthenticationUnavailable,
    );
  }

  await assertRejects(
    () => verifySupabaseAccessToken("test.jwt", {
      ...authenticationDependencies,
      timeoutMs: 1,
      http: async (_url, init) => {
        await new Promise<never>((_resolve, reject) => {
          (init.signal as AbortSignal).addEventListener(
            "abort",
            () => reject(new DOMException("aborted", "AbortError")),
            { once: true },
          );
        });
      },
    }),
    AuthenticationUnavailable,
  );
});

Deno.test("does not call validator cache or Overpass after any authentication failure", async () => {
  for (const [expectedStatus, authenticate] of [
    [401, async () => false],
    [503, async () => {
      throw new AuthenticationUnavailable();
    }],
  ]) {
    let downstreamCalls = 0;
    const handler = createNearbyFuelStationsHandler({
      authenticate,
      validator: {
        validate: async () => {
          downstreamCalls += 1;
          return { validationStatus: "inside" };
        },
      },
      cache: {
        get: async () => {
          downstreamCalls += 1;
          return null;
        },
        put: async (_candidate, value) => {
          downstreamCalls += 1;
          return value;
        },
      },
      http: async () => {
        downstreamCalls += 1;
        return overpassResponse();
      },
    });
    const response = await handler(new Request("https://edge.example/function", {
      method: "POST",
      headers: {
        authorization: "Bearer test.jwt",
        "content-type": "application/json",
      },
      body: '{"latitude":5,"longitude":116,"analysis_radius_km":5}',
    }));
    assertEquals(response.status, expectedStatus);
    assertEquals(downstreamCalls, 0);
  }
});

Deno.test("proves both cache RPC source bodies reject NULL analysis radii", async () => {
  const migration = await Deno.readTextFile(new URL(
    "../../migrations/202608200001_module2_osm_fuel_station_cache.sql",
    import.meta.url,
  ));
  for (const [signature, terminator] of [
    [
      "create function public.nearby_fuel_station_cache_get(",
      "create function public.nearby_fuel_station_cache_put(",
    ],
    [
      "create function public.nearby_fuel_station_cache_put(",
      "revoke all privileges on function public.nearby_fuel_station_cache_get(",
    ],
  ]) {
    const start = migration.indexOf(signature);
    const end = migration.indexOf(terminator, start + signature.length);
    assert(start >= 0 && end > start, `Missing ${signature}`);
    assert(
      migration.slice(start, end).includes("p_analysis_radius_km is null"),
      `${signature} must reject NULL analysis radii.`,
    );
  }
});

Deno.test("rejects missing and malformed authorization before any downstream call", async () => {
  let downstreamCalls = 0;
  const handler = createNearbyFuelStationsHandler({
    authenticate: async () => {
      downstreamCalls += 1;
      return true;
    },
    validator: { validate: async () => ({ validationStatus: "inside" }) },
    cache: {
      get: async () => null,
      put: async (_candidate, value) => value,
    },
    http: async () => {
      downstreamCalls += 1;
      return overpassResponse();
    },
  });
  for (const authorization of [null, "Basic credentials"]) {
    const headers = new Headers();
    if (authorization !== null) headers.set("authorization", authorization);
    const response = await handler(new Request("https://edge.example/function", {
      method: "POST",
      headers,
    }));
    assertEquals(response.status, 401);
  }
  assertEquals(downstreamCalls, 0);
});

Deno.test("fails closed for outside unverified and boundary-review validation statuses", async () => {
  for (const validationStatus of [
    "outside",
    "unverified",
    "boundary_review_required",
  ]) {
    let httpCalls = 0;
    await assertRejects(
      () => loadNearbyFuelStations(request, "test.jwt", {
        validator: { validate: async () => ({ validationStatus }) },
        cache: {
          get: async () => null,
          put: async (_request, result) => result,
        },
        http: async () => {
          httpCalls += 1;
          throw new Error("must not call upstream");
        },
      }),
      SiteNotValidatedInside,
    );
    assertEquals(httpCalls, 0);
  }
});

Deno.test("uses an exact cache hit and does not reuse a neighbouring coordinate", async () => {
  const cached = nearbyResult(request);
  let httpCalls = 0;
  const cache = {
    get: async (candidate: typeof request) =>
      candidate.latitude === request.latitude &&
        candidate.longitude === request.longitude &&
        candidate.analysisRadiusKm === request.analysisRadiusKm
        ? cached
        : null,
    put: async (_candidate: typeof request, result: typeof cached) => result,
  };
  const dependencies = {
    validator: { validate: async () => ({ validationStatus: "inside" }) },
    cache,
    http: async () => {
      httpCalls += 1;
      return overpassResponse();
    },
  };
  assertEquals(
    (await loadNearbyFuelStations(request, "test.jwt", dependencies)).fetchedAt,
    cached.fetchedAt,
  );
  const neighbouring = validateNearbyFuelStationsRequest({
    latitude: request.latitude,
    longitude: request.longitude + 0.0000001,
    analysisRadiusKm: 5,
  });
  await loadNearbyFuelStations(neighbouring, "test.jwt", dependencies);
  assertEquals(httpCalls, 1);
});

Deno.test("treats expired and failed cache reads as cache misses", async () => {
  for (const get of [
    async () => null,
    async () => {
      throw new Error("cache unavailable");
    },
  ]) {
    let httpCalls = 0;
    const result = await loadNearbyFuelStations(request, "test.jwt", {
      validator: { validate: async () => ({ validationStatus: "inside" }) },
      cache: {
        get,
        put: async (_candidate, value) => value,
      },
      http: async () => {
        httpCalls += 1;
        return overpassResponse();
      },
    });
    assertEquals(httpCalls, 1);
    assertEquals(result.source, "openstreetmap");
  }
});

Deno.test("rejects malformed cached station results as safe cache misses", () => {
  const valid = cachedPublicResult(request);

  for (const mutate of [
    (value: Record<string, unknown>) => {
      value.station_count = 2;
    },
    (value: Record<string, unknown>) => {
      value.station_count = 101;
      const stations = value.stations as Record<string, unknown>[];
      value.stations = Array.from({ length: 101 }, () => stations[0]);
    },
    (value: Record<string, unknown>) => {
      (value.stations as Record<string, unknown>[])[0].osm_type = "invalid";
    },
    (value: Record<string, unknown>) => {
      (value.stations as Record<string, unknown>[])[0].osm_id = "01";
    },
    (value: Record<string, unknown>) => {
      (value.stations as Record<string, unknown>[])[0].latitude = 91;
    },
    (value: Record<string, unknown>) => {
      (value.stations as Record<string, unknown>[])[0].distance_km = -1;
    },
    (value: Record<string, unknown>) => {
      value.nearest_distance_km = null;
    },
    (value: Record<string, unknown>) => {
      (value.stations as Record<string, unknown>[])[0].unexpected = true;
    },
  ]) {
    const malformed = structuredClone(valid) as Record<string, unknown>;
    mutate(malformed);
    assertThrows(
      () => parseCachedNearbyFuelStationsResult(
        malformed,
        request,
        "2026-08-20T00:00:00.000Z",
      ),
      Error,
    );
  }
});

Deno.test("uses fresh Overpass evidence after a malformed cache row", async () => {
  let upstreamCalls = 0;
  const result = await loadNearbyFuelStations(request, "test.jwt", {
    validator: { validate: async () => ({ validationStatus: "inside" }) },
    cache: {
      get: async () => {
        const malformed = cachedPublicResult(request) as Record<string, unknown>;
        malformed.station_count = 2;
        return parseCachedNearbyFuelStationsResult(
          malformed,
          request,
          "2026-08-20T00:00:00.000Z",
        );
      },
      put: async (_candidate, fresh) => fresh,
    },
    http: async () => {
      upstreamCalls += 1;
      return overpassResponse();
    },
  });
  assertEquals(upstreamCalls, 1);
  assertEquals(result.stationCount, 1);
});

Deno.test("returns fresh evidence when cache write fails and concurrent upserts remain safe", async () => {
  const rows = new Map<string, unknown>();
  const cache = {
    get: async () => null,
    put: async (candidate: typeof request, result: ReturnType<typeof nearbyResult>) => {
      const key = `${candidate.latitude}:${candidate.longitude}:${candidate.analysisRadiusKm}`;
      rows.set(key, result);
      return result;
    },
  };
  const dependencies = {
    validator: { validate: async () => ({ validationStatus: "inside" }) },
    cache,
    http: async () => overpassResponse(),
  };
  const results = await Promise.all([
    loadNearbyFuelStations(request, "test.jwt", dependencies),
    loadNearbyFuelStations(request, "test.jwt", dependencies),
  ]);
  assertEquals(results.length, 2);
  assertEquals(rows.size, 1);

  const fresh = await loadNearbyFuelStations(request, "test.jwt", {
    validator: { validate: async () => ({ validationStatus: "inside" }) },
    cache: {
      get: async () => null,
      put: async () => {
        throw new Error("cache write unavailable");
      },
    },
    http: async () => overpassResponse(),
  });
  assertEquals(fresh.source, "openstreetmap");
});

Deno.test("bounds and neutralizes fixed Overpass HTTP responses", async () => {
  const declared = trackedBytesStream("{}");
  let declaredAbortSignal: AbortSignal | undefined;
  await assertRejects(
    () => fetchFixedOverpassPayload(
      async (_url, init) => {
        declaredAbortSignal = init.signal as AbortSignal;
        return new Response(declared.stream, {
          status: 200,
          headers: { "content-length": String(maximumOverpassResponseBytes + 1) },
        });
      },
      request,
    ),
    UpstreamFuelStationsFailure,
  );
  assertEquals(declared.cancellationCount(), 1);
  assertEquals(declaredAbortSignal?.aborted, true);

  const streamed = trackedBytesStream(
    new Uint8Array(maximumOverpassResponseBytes + 1),
  );
  let streamedAbortSignal: AbortSignal | undefined;
  await assertRejects(
    () => fetchFixedOverpassPayload(
      async (_url, init) => {
        streamedAbortSignal = init.signal as AbortSignal;
        return new Response(streamed.stream);
      },
      request,
    ),
    UpstreamFuelStationsFailure,
  );
  assertEquals(streamed.cancellationCount(), 1);
  assertEquals(streamedAbortSignal?.aborted, true);

  const rejectingOverflow = trackedBytesStream(
    new Uint8Array(maximumOverpassResponseBytes + 1),
    { rejectCancellation: true },
  );
  await assertRejects(
    () => fetchFixedOverpassPayload(
      async () => new Response(rejectingOverflow.stream),
      request,
    ),
    UpstreamFuelStationsFailure,
  );
  assertEquals(rejectingOverflow.cancellationCount(), 1);
  await assertRejects(
    () => fetchFixedOverpassPayload(async () => new Response("{}", { status: 503 }), request),
    UpstreamFuelStationsFailure,
  );
  await assertRejects(
    () => fetchFixedOverpassPayload(async () => new Response(null, { status: 200 }), request),
    UpstreamFuelStationsFailure,
  );
  await assertRejects(
    () => fetchFixedOverpassPayload(
      async () => new Response(bytesStream(new Uint8Array([0xff]))),
      request,
    ),
    UpstreamFuelStationsFailure,
  );
  await assertRejects(
    () => fetchFixedOverpassPayload(async () => new Response("not json"), request),
    UpstreamFuelStationsFailure,
  );
  await assertRejects(
    () => loadNearbyFuelStations(request, "test.jwt", {
      validator: { validate: async () => ({ validationStatus: "inside" }) },
      cache: { get: async () => null, put: async (_candidate, result) => result },
      http: async () => new Response("[]"),
    }),
    UpstreamFuelStationsFailure,
  );
});

Deno.test("keeps the timeout active while the Overpass response body is read", async () => {
  const timedOut = trackedNeverEndingStream();
  let timeoutSignal: AbortSignal | undefined;
  await assertRejects(
    () => fetchFixedOverpassPayload(
      async (_url, init) => {
        timeoutSignal = init.signal as AbortSignal;
        return new Response(timedOut.stream);
      },
      request,
      1,
    ),
    UpstreamFuelStationsFailure,
  );
  assertEquals(timedOut.cancelled(), true);
  assertEquals(timedOut.cancellationCount(), 1);
  assertEquals(timeoutSignal?.aborted, true);

  const rejectingTimedOut = trackedNeverEndingStream({
    rejectCancellation: true,
  });
  await assertRejects(
    () => fetchFixedOverpassPayload(
      async () => new Response(rejectingTimedOut.stream),
      request,
      1,
    ),
    UpstreamFuelStationsFailure,
  );
  assertEquals(rejectingTimedOut.cancellationCount(), 1);
});

Deno.test("preserves OSM identifier precision and verifies distance and limits", () => {
  const stations = parseOverpassFuelStations({
    elements: [
      { type: "node", id: Number.MAX_SAFE_INTEGER + 1, lat: 5, lon: 116 },
      { type: "node", id: "900719925474099312345", lat: 5, lon: 116 },
    ],
  }, request);
  assertEquals(stations.map((station) => station.osmId), ["900719925474099312345"]);
  const oneDegreeAtEquatorKm = haversineDistanceKm(0, 0, 0, 1);
  assert(Math.abs(oneDegreeAtEquatorKm - 111.1950802335) < 0.000001);

  const elements = Array.from({ length: maximumReturnedStationCount + 1 }, (_, index) => ({
    type: "node",
    id: index + 1,
    lat: request.latitude,
    lon: request.longitude,
  }));
  assertEquals(
    parseOverpassFuelStations({ elements }, request).length,
    maximumReturnedStationCount,
  );
});

Deno.test("sends only responsible fixed Overpass headers", async () => {
  let headers: Headers | undefined;
  await fetchFixedOverpassPayload(
    async (_url, init) => {
      headers = new Headers(init.headers);
      return new Response('{"elements":[]}');
    },
    request,
  );
  assertEquals(headers?.get("content-type"), "application/x-www-form-urlencoded;charset=UTF-8");
  assertEquals(headers?.get("accept"), "application/json");
  assertEquals(headers?.get("user-agent"), overpassUserAgent);
});

function bytesStream(value: string | Uint8Array): ReadableStream<Uint8Array> {
  const bytes = typeof value === "string" ? new TextEncoder().encode(value) : value;
  return new ReadableStream({
    start(controller) {
      controller.enqueue(bytes);
      controller.close();
    },
  });
}

function trackedBytesStream(
  value: string | Uint8Array,
  options: { rejectCancellation?: boolean } = {},
): {
  stream: ReadableStream<Uint8Array>;
  cancellationCount: () => number;
} {
  let cancellationCount = 0;
  const bytes = typeof value === "string" ? new TextEncoder().encode(value) : value;
  return {
    stream: new ReadableStream({
      start(controller) {
        controller.enqueue(bytes);
      },
      cancel() {
        cancellationCount += 1;
        if (options.rejectCancellation === true) {
          return Promise.reject(new Error("cancel failure"));
        }
      },
    }),
    cancellationCount: () => cancellationCount,
  };
}

function trackedNeverEndingStream(
  options: { rejectCancellation?: boolean } = {},
): {
  stream: ReadableStream<Uint8Array>;
  cancelled: () => boolean;
  cancellationCount: () => number;
} {
  let wasCancelled = false;
  let cancellationCount = 0;
  return {
    stream: new ReadableStream({
      start() {},
      cancel() {
        wasCancelled = true;
        cancellationCount += 1;
        if (options.rejectCancellation === true) {
          return Promise.reject(new Error("cancel failure"));
        }
      },
    }),
    cancelled: () => wasCancelled,
    cancellationCount: () => cancellationCount,
  };
}

function overpassResponse(): Response {
  return new Response(JSON.stringify({
    elements: [{ type: "node", id: 1, lat: 5.9805, lon: 116.0736 }],
  }));
}

function nearbyResult(candidate: typeof request) {
  return {
    source: "openstreetmap" as const,
    attribution: openStreetMapAttribution,
    attributionUrl: openStreetMapAttributionUrl,
    fetchedAt: "2026-08-20T00:00:00.000Z",
    analysisRadiusKm: candidate.analysisRadiusKm,
    latitude: candidate.latitude,
    longitude: candidate.longitude,
    stationCount: 0,
    nearestDistanceKm: null,
    stations: [],
  };
}

function cachedPublicResult(candidate: typeof request): Record<string, unknown> {
  return toNearbyFuelStationsPublicResponse({
    ...nearbyResult(candidate),
    stationCount: 1,
    nearestDistanceKm: 0.1,
    stations: [{
      osmType: "node",
      osmId: "1",
      name: null,
      brand: null,
      operator: null,
      latitude: candidate.latitude,
      longitude: candidate.longitude,
      distanceKm: 0.1,
    }],
  });
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
