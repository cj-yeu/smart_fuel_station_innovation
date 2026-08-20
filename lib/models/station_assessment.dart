import 'dart:convert';
import 'dart:typed_data';

import 'assessment_site_candidate.dart';
import 'east_malaysia_territory.dart';
import 'geo_point.dart';

enum StationAssessmentGeographicStatus {
  legacyUnverified,
  unverified,
  inside,
  outside,
  boundaryReviewRequired,
}

class StationAssessment {
  final String id;
  final String userId;
  final String? companyId;
  final String locationName;
  final double populationDensity;
  final int trafficLevel;
  final int registeredVehicleCount;
  final int nearbyFuelStations;
  final double competitorDistanceKm;
  final int roadAccessibility;
  final int commercialActivity;
  final int residentialActivity;
  final int landAccessibility;
  final double finalScore;
  final String suitabilityCategory;
  final String recommendation;
  final String explanation;
  final GeoPoint? siteLocation;
  final int? analysisRadiusKm;
  final StationAssessmentGeographicStatus geographicValidationStatus;
  final EastMalaysiaTerritory? confirmedTerritory;
  final String? boundaryDatasetId;
  final DateTime? geographicallyValidatedAt;
  final String? validatedCreateRequestId;
  final DateTime createdAt;
  final DateTime updatedAt;

  StationAssessment({
    required this.id,
    required this.userId,
    required this.companyId,
    required this.locationName,
    required this.populationDensity,
    required this.trafficLevel,
    required this.registeredVehicleCount,
    required this.nearbyFuelStations,
    required this.competitorDistanceKm,
    required this.roadAccessibility,
    required this.commercialActivity,
    required this.residentialActivity,
    required this.landAccessibility,
    required this.finalScore,
    required this.suitabilityCategory,
    required this.recommendation,
    required this.explanation,
    this.siteLocation,
    this.analysisRadiusKm,
    this.geographicValidationStatus =
        StationAssessmentGeographicStatus.legacyUnverified,
    this.confirmedTerritory,
    this.boundaryDatasetId,
    this.geographicallyValidatedAt,
    this.validatedCreateRequestId,
    required this.createdAt,
    required this.updatedAt,
  }) {
    _validateGeographicState(
      siteLocation: siteLocation,
      analysisRadiusKm: analysisRadiusKm,
      status: geographicValidationStatus,
      confirmedTerritory: confirmedTerritory,
      boundaryDatasetId: boundaryDatasetId,
      geographicallyValidatedAt: geographicallyValidatedAt,
    );
  }

  factory StationAssessment.fromMap(Map<String, dynamic> map) {
    final hasGeographicStatus = map.containsKey('geographic_validation_status');

    return StationAssessment(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      companyId: map['company_id'] as String?,
      locationName: map['location_name'] as String,
      populationDensity: (map['population_density'] as num).toDouble(),
      trafficLevel: map['traffic_level'] as int,
      registeredVehicleCount: map['registered_vehicle_count'] as int,
      nearbyFuelStations: map['nearby_fuel_stations'] as int,
      competitorDistanceKm: (map['competitor_distance_km'] as num).toDouble(),
      roadAccessibility: map['road_accessibility'] as int,
      commercialActivity: map['commercial_activity'] as int,
      residentialActivity: map['residential_activity'] as int,
      landAccessibility: map['land_accessibility'] as int,
      finalScore: (map['final_score'] as num).toDouble(),
      suitabilityCategory: map['suitability_category'] as String,
      recommendation: map['recommendation'] as String,
      explanation: map['explanation'] as String,
      siteLocation: _parseSiteLocation(map['site_location']),
      analysisRadiusKm: _parseAnalysisRadius(map['analysis_radius_km']),
      geographicValidationStatus: hasGeographicStatus
          ? _parseGeographicStatus(map['geographic_validation_status'])
          : StationAssessmentGeographicStatus.legacyUnverified,
      confirmedTerritory: _parseTerritory(map['confirmed_territory']),
      boundaryDatasetId: _parseBoundaryDatasetId(map['boundary_dataset_id']),
      geographicallyValidatedAt: _parseNullableDateTime(
        map['geographically_validated_at'],
      ),
      validatedCreateRequestId: _parseNullableUuid(
        map['validated_create_request_id'],
        fieldName: 'validated create request ID',
      ),
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  static GeoPoint? _parseSiteLocation(Object? value) {
    if (value == null) return null;

    Object? decoded = value;
    if (value is String) {
      final wireValue = value.trim();
      if (wireValue.startsWith('{')) {
        try {
          decoded = jsonDecode(wireValue);
        } on FormatException {
          throw const FormatException('Assessment site location is malformed.');
        }
      } else {
        return _parseEwkbPoint(wireValue);
      }
    }

    if (decoded is! Map || decoded['type'] != 'Point') {
      throw const FormatException(
        'Assessment site location must be a GeoJSON Point.',
      );
    }

    final coordinates = decoded['coordinates'];
    if (coordinates is! List ||
        coordinates.length != 2 ||
        coordinates[0] is! num ||
        coordinates[1] is! num) {
      throw const FormatException(
        'Assessment site location coordinates are malformed.',
      );
    }

    return _checkedGeoPoint(
      longitude: (coordinates[0] as num).toDouble(),
      latitude: (coordinates[1] as num).toDouble(),
    );
  }

  static GeoPoint _parseEwkbPoint(String value) {
    final hex = value.startsWith(r'\x') ? value.substring(2) : value;
    if (hex.length != 50 || !RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex)) {
      throw const FormatException(
        'Assessment site location EWKB is malformed.',
      );
    }

    final bytes = Uint8List(hex.length ~/ 2);
    for (var index = 0; index < bytes.length; index++) {
      bytes[index] = int.parse(
        hex.substring(index * 2, index * 2 + 2),
        radix: 16,
      );
    }

    final endian = switch (bytes[0]) {
      0 => Endian.big,
      1 => Endian.little,
      _ => throw const FormatException(
        'Assessment site location EWKB byte order is invalid.',
      ),
    };
    final data = ByteData.sublistView(bytes);
    final geometryType = data.getUint32(1, endian);
    const hasZ = 0x80000000;
    const hasM = 0x40000000;
    const hasSrid = 0x20000000;
    const baseTypeMask = 0x1fffffff;

    if (geometryType & (hasZ | hasM) != 0 ||
        geometryType & hasSrid == 0 ||
        geometryType & baseTypeMask != 1) {
      throw const FormatException(
        'Assessment site location EWKB must be a two-dimensional Point.',
      );
    }
    if (data.getUint32(5, endian) != 4326) {
      throw const FormatException(
        'Assessment site location EWKB must use SRID 4326.',
      );
    }

    return _checkedGeoPoint(
      longitude: data.getFloat64(9, endian),
      latitude: data.getFloat64(17, endian),
    );
  }

  static GeoPoint _checkedGeoPoint({
    required double latitude,
    required double longitude,
  }) {
    try {
      return GeoPoint(latitude: latitude, longitude: longitude);
    } on ArgumentError {
      throw const FormatException(
        'Assessment site location coordinates are invalid.',
      );
    }
  }

  static int? _parseAnalysisRadius(Object? value) {
    if (value == null) return null;
    if (value is! num || value.toInt() != value) {
      throw const FormatException(
        'Assessment analysis radius must be an integer.',
      );
    }

    final radius = value.toInt();
    if (!AssessmentSiteCandidate.supportedAnalysisRadiiKm.contains(
      radius.toDouble(),
    )) {
      throw const FormatException(
        'Assessment analysis radius must be 3, 5, or 10 kilometres.',
      );
    }
    return radius;
  }

  static StationAssessmentGeographicStatus _parseGeographicStatus(
    Object? value,
  ) {
    return switch (value) {
      'legacy_unverified' => StationAssessmentGeographicStatus.legacyUnverified,
      'unverified' => StationAssessmentGeographicStatus.unverified,
      'inside' => StationAssessmentGeographicStatus.inside,
      'outside' => StationAssessmentGeographicStatus.outside,
      'boundary_review_required' =>
        StationAssessmentGeographicStatus.boundaryReviewRequired,
      _ => throw FormatException(
        'Unknown or missing assessment geographic validation status: $value',
      ),
    };
  }

  static EastMalaysiaTerritory? _parseTerritory(Object? value) {
    if (value == null) return null;
    if (value is! String) {
      throw const FormatException(
        'Assessment confirmed territory must be a string.',
      );
    }
    try {
      return EastMalaysiaTerritory.fromStorageValue(value);
    } on ArgumentError {
      throw FormatException('Unknown assessment territory: $value');
    }
  }

  static String? _parseBoundaryDatasetId(Object? value) {
    return _parseNullableUuid(value, fieldName: 'boundary dataset ID');
  }

  static String? _parseNullableUuid(
    Object? value, {
    required String fieldName,
  }) {
    if (value == null) return null;
    if (value is! String ||
        !RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
          caseSensitive: false,
        ).hasMatch(value)) {
      throw FormatException('Assessment $fieldName must be a valid UUID.');
    }
    return value;
  }

  static DateTime? _parseNullableDateTime(Object? value) {
    if (value == null) return null;
    if (value is! String) {
      throw const FormatException(
        'Assessment geographic validation timestamp is malformed.',
      );
    }
    return DateTime.parse(value);
  }

  static void _validateGeographicState({
    required GeoPoint? siteLocation,
    required int? analysisRadiusKm,
    required StationAssessmentGeographicStatus status,
    required EastMalaysiaTerritory? confirmedTerritory,
    required String? boundaryDatasetId,
    required DateTime? geographicallyValidatedAt,
  }) {
    if (analysisRadiusKm != null &&
        !AssessmentSiteCandidate.supportedAnalysisRadiiKm.contains(
          analysisRadiusKm.toDouble(),
        )) {
      throw const FormatException(
        'Assessment analysis radius must be 3, 5, or 10 kilometres.',
      );
    }

    final pointAndRadiusMatch =
        (siteLocation == null) == (analysisRadiusKm == null);
    final noProvenance =
        confirmedTerritory == null &&
        boundaryDatasetId == null &&
        geographicallyValidatedAt == null;

    final isValid = switch (status) {
      StationAssessmentGeographicStatus.legacyUnverified =>
        siteLocation == null && analysisRadiusKm == null && noProvenance,
      StationAssessmentGeographicStatus.unverified =>
        pointAndRadiusMatch && noProvenance,
      StationAssessmentGeographicStatus.inside =>
        siteLocation != null &&
            analysisRadiusKm != null &&
            confirmedTerritory != null &&
            boundaryDatasetId != null &&
            geographicallyValidatedAt != null,
      StationAssessmentGeographicStatus.outside ||
      StationAssessmentGeographicStatus.boundaryReviewRequired =>
        siteLocation != null &&
            analysisRadiusKm != null &&
            confirmedTerritory == null &&
            boundaryDatasetId != null &&
            geographicallyValidatedAt != null,
    };

    if (!isValid) {
      throw const FormatException(
        'Assessment geographic fields contain an inconsistent validation state.',
      );
    }
  }
}
