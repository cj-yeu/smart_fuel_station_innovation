import 'assessment_site_candidate.dart';
import 'geo_point.dart';
import 'nearby_fuel_station.dart';

class NearbyFuelStationResult {
  static const sourceOpenStreetMap = 'openstreetmap';
  static const openStreetMapAttribution = '© OpenStreetMap contributors';
  static const openStreetMapAttributionUrl =
      'https://www.openstreetmap.org/copyright';

  final String source;
  final String attribution;
  final String attributionUrl;
  final DateTime fetchedAt;
  final double analysisRadiusKm;
  final GeoPoint point;
  final int stationCount;
  final double? nearestDistanceKm;
  final List<NearbyFuelStation> stations;

  NearbyFuelStationResult({
    required this.source,
    required this.attribution,
    required this.attributionUrl,
    required this.fetchedAt,
    required this.analysisRadiusKm,
    required this.point,
    required this.stationCount,
    required this.nearestDistanceKm,
    required List<NearbyFuelStation> stations,
  }) : stations = List.unmodifiable(stations) {
    if (source != sourceOpenStreetMap ||
        attribution != openStreetMapAttribution ||
        attributionUrl != openStreetMapAttributionUrl) {
      throw ArgumentError('Unexpected nearby fuel-station source metadata.');
    }
    if (!AssessmentSiteCandidate.supportedAnalysisRadiiKm.contains(
      analysisRadiusKm,
    )) {
      throw ArgumentError.value(
        analysisRadiusKm,
        'analysisRadiusKm',
        'Analysis radius must be exactly 3, 5, or 10 kilometres.',
      );
    }
    if (stationCount < 0 || stationCount > 100 || stationCount != stations.length) {
      throw ArgumentError('Station count must match at most 100 station rows.');
    }
    if (stationCount == 0 && nearestDistanceKm != null) {
      throw ArgumentError('An empty result must not have a nearest distance.');
    }
    if (stationCount > 0 &&
        (nearestDistanceKm == null ||
            !nearestDistanceKm.isFinite ||
            nearestDistanceKm < 0 ||
            nearestDistanceKm != stations.first.distanceKm)) {
      throw ArgumentError(
        'A non-empty result requires its nearest station distance.',
      );
    }
  }

  factory NearbyFuelStationResult.fromMap({
    required Map<String, dynamic> row,
    required GeoPoint expectedPoint,
    required double expectedAnalysisRadiusKm,
  }) {
    final point = GeoPoint(
      latitude: _requiredDouble(row['latitude'], 'latitude'),
      longitude: _requiredDouble(row['longitude'], 'longitude'),
    );
    if (!_sameCoordinate(point.latitude, expectedPoint.latitude) ||
        !_sameCoordinate(point.longitude, expectedPoint.longitude)) {
      throw const FormatException(
        'Nearby fuel-station coordinates did not match the validated site.',
      );
    }

    final radius = _requiredDouble(
      row['analysis_radius_km'],
      'analysis_radius_km',
    );
    if (radius != expectedAnalysisRadiusKm) {
      throw const FormatException(
        'Nearby fuel-station radius did not match the validated site.',
      );
    }

    final stationsValue = row['stations'];
    if (stationsValue is! List) {
      throw const FormatException('Nearby fuel-station stations must be a list.');
    }
    final stations = stationsValue
        .map((value) {
          if (value is! Map) {
            throw const FormatException('Nearby fuel-station row is invalid.');
          }
          return NearbyFuelStation.fromMap(Map<String, dynamic>.from(value));
        })
        .toList(growable: false);

    return NearbyFuelStationResult(
      source: _requiredString(row['source'], 'source'),
      attribution: _requiredString(row['attribution'], 'attribution'),
      attributionUrl: _requiredString(row['attribution_url'], 'attribution_url'),
      fetchedAt: _parseDateTime(row['fetched_at']),
      analysisRadiusKm: radius,
      point: point,
      stationCount: _requiredInt(row['station_count'], 'station_count'),
      nearestDistanceKm: _nullableDouble(
        row['nearest_distance_km'],
        'nearest_distance_km',
      ),
      stations: stations,
    );
  }

  static bool _sameCoordinate(double first, double second) =>
      first == second || (first == 0 && second == 0);

  static String _requiredString(Object? value, String fieldName) {
    if (value is String && value.isNotEmpty) return value;
    throw FormatException('Nearby fuel-station $fieldName must be a string.');
  }

  static int _requiredInt(Object? value, String fieldName) {
    if (value is int) return value;
    throw FormatException('Nearby fuel-station $fieldName must be an integer.');
  }

  static double _requiredDouble(Object? value, String fieldName) {
    if (value is num && value.toDouble().isFinite) return value.toDouble();
    throw FormatException('Nearby fuel-station $fieldName must be finite.');
  }

  static double? _nullableDouble(Object? value, String fieldName) {
    if (value == null) return null;
    return _requiredDouble(value, fieldName);
  }

  static DateTime _parseDateTime(Object? value) {
    if (value is! String) {
      throw const FormatException('Nearby fuel-station fetched_at is invalid.');
    }
    return DateTime.tryParse(value) ??
        (throw const FormatException(
          'Nearby fuel-station fetched_at is invalid.',
        ));
  }
}
