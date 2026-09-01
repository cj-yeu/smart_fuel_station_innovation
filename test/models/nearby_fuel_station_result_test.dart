import 'package:flutter_test/flutter_test.dart';
import 'package:smart_fuel_station_innovation/models/geo_point.dart';
import 'package:smart_fuel_station_innovation/models/nearby_fuel_station_result.dart';

void main() {
  final point = GeoPoint(latitude: 5.9804, longitude: 116.0735);

  Map<String, dynamic> resultRow({
    int count = 1,
    Object? nearestDistance = 1.25,
    List<Map<String, dynamic>>? stations,
  }) {
    return {
      'source': 'openstreetmap',
      'attribution': '© OpenStreetMap contributors',
      'attribution_url': 'https://www.openstreetmap.org/copyright',
      'fetched_at': '2026-08-20T00:00:00.000Z',
      'analysis_radius_km': 5,
      'latitude': point.latitude,
      'longitude': point.longitude,
      'station_count': count,
      'nearest_distance_km': nearestDistance,
      'stations': stations ??
          [
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

  test('parses a complete OSM result for the validated point and radius', () {
    final result = NearbyFuelStationResult.fromMap(
      row: resultRow(),
      expectedPoint: point,
      expectedAnalysisRadiusKm: 5,
    );

    expect(result.stationCount, 1);
    expect(result.nearestDistanceKm, 1.25);
    expect(result.stations.single.osmId, '123');
  });

  test('accepts an empty result only with a null nearest distance', () {
    final result = NearbyFuelStationResult.fromMap(
      row: resultRow(count: 0, nearestDistance: null, stations: const []),
      expectedPoint: point,
      expectedAnalysisRadiusKm: 5,
    );

    expect(result.stations, isEmpty);
    expect(result.nearestDistanceKm, isNull);
  });

  test('rejects mismatched site coordinates and invalid station shapes', () {
    final mismatched = resultRow()..['latitude'] = 5.9;
    expect(
      () => NearbyFuelStationResult.fromMap(
        row: mismatched,
        expectedPoint: point,
        expectedAnalysisRadiusKm: 5,
      ),
      throwsFormatException,
    );

    final malformed = resultRow(
      stations: [
        {
          'osm_type': 'planet',
          'osm_id': '123',
          'name': null,
          'brand': null,
          'operator': null,
          'latitude': point.latitude,
          'longitude': point.longitude,
          'distance_km': 1.25,
        },
      ],
    );
    expect(
      () => NearbyFuelStationResult.fromMap(
        row: malformed,
        expectedPoint: point,
        expectedAnalysisRadiusKm: 5,
      ),
      throwsArgumentError,
    );
  });
}
