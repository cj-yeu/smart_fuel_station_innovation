import 'package:flutter_test/flutter_test.dart';
import 'package:smart_fuel_station_innovation/models/east_malaysia_site_validation_result.dart';
import 'package:smart_fuel_station_innovation/models/east_malaysia_territory.dart';
import 'package:smart_fuel_station_innovation/models/geo_point.dart';
import 'package:smart_fuel_station_innovation/services/nearby_fuel_station_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  final validationResult = EastMalaysiaSiteValidationResult.fromRpcRow(
    row: {
      'validation_status': 'inside',
      'confirmed_territory': EastMalaysiaTerritory.sabah.storageValue,
      'boundary_dataset_id': '123e4567-e89b-12d3-a456-426614174000',
    },
    point: GeoPoint(latitude: 5.9804, longitude: 116.0735),
    analysisRadiusKm: 5,
  );

  test('calls the Edge Function with the exact validated site payload', () async {
    String? invokedName;
    Map<String, dynamic>? invokedBody;
    final repository = NearbyFuelStationRepository(
      SupabaseClient('https://example.invalid', 'test-anon-key'),
      sessionProvider: () => true,
      functionCaller: (name, body) async {
        invokedName = name;
        invokedBody = body;
        return responseFor(validationResult);
      },
    );

    final result = await repository.fetchForValidatedSite(validationResult);

    expect(invokedName, 'nearby-fuel-stations');
    expect(invokedBody, {
      'latitude': 5.9804,
      'longitude': 116.0735,
      'analysis_radius_km': 5,
    });
    expect(result.stationCount, 1);
  });

  test('requires a session before invoking the Edge Function', () async {
    var invoked = false;
    final repository = NearbyFuelStationRepository(
      SupabaseClient('https://example.invalid', 'test-anon-key'),
      sessionProvider: () => false,
      functionCaller: (_, _) async {
        invoked = true;
        return responseFor(validationResult);
      },
    );

    await expectLater(
      repository.fetchForValidatedSite(validationResult),
      throwsStateError,
    );
    expect(invoked, isFalse);
  });
}

Map<String, dynamic> responseFor(EastMalaysiaSiteValidationResult validation) {
  final point = validation.candidate.point;
  return {
    'source': 'openstreetmap',
    'attribution': '© OpenStreetMap contributors',
    'attribution_url': 'https://www.openstreetmap.org/copyright',
    'fetched_at': '2026-08-20T00:00:00.000Z',
    'analysis_radius_km': 5,
    'latitude': point.latitude,
    'longitude': point.longitude,
    'station_count': 1,
    'nearest_distance_km': 1.25,
    'stations': [
      {
        'osm_type': 'node',
        'osm_id': '123',
        'name': 'Synthetic Fuel',
        'brand': null,
        'operator': null,
        'latitude': point.latitude,
        'longitude': point.longitude,
        'distance_km': 1.25,
      },
    ],
  };
}
