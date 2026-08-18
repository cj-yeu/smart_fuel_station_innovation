import 'dart:convert';

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
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  static GeoPoint? _parseSiteLocation(Object? value) {
    if (value == null) return null;

    Object? decoded = value;
    if (value is String) {
      try {
        decoded = jsonDecode(value);
      } on FormatException {
        throw const FormatException('Assessment site location is malformed.');
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

    return GeoPoint(
      longitude: (coordinates[0] as num).toDouble(),
      latitude: (coordinates[1] as num).toDouble(),
    );
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
    if (value == null) return null;
    if (value is! String ||
        !RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
          caseSensitive: false,
        ).hasMatch(value)) {
      throw const FormatException(
        'Assessment boundary dataset ID must be a valid UUID.',
      );
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
