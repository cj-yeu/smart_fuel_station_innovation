import 'dart:convert';

import 'east_malaysia_site_validation_result.dart';
import 'station_assessment_create_input.dart';

class StationAssessmentValidatedCreateInput {
  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  final StationAssessmentCreateInput content;
  final EastMalaysiaSiteValidationResult validationResult;
  final String requestId;

  StationAssessmentValidatedCreateInput({
    required this.content,
    required this.validationResult,
    required this.requestId,
  }) {
    if (!validationResult.candidate.isValidatedInside ||
        validationResult.boundaryDatasetId == null) {
      throw ArgumentError(
        'Validated assessment creation requires an authoritative inside result '
        'with boundary dataset provenance.',
      );
    }
    if (!_uuidPattern.hasMatch(requestId)) {
      throw ArgumentError.value(
        requestId,
        'requestId',
        'Validated assessment request ID must be a UUID.',
      );
    }
  }

  Map<String, dynamic> toRpcParams() {
    final candidate = validationResult.candidate;

    return {
      for (final entry in content.toInsertMap().entries)
        'p_${entry.key}': entry.value,
      'p_latitude': candidate.point.latitude,
      'p_longitude': candidate.point.longitude,
      'p_analysis_radius_km': candidate.analysisRadiusKm.toInt(),
      'p_expected_boundary_dataset_id': validationResult.boundaryDatasetId,
      'p_request_id': requestId,
    };
  }

  static String payloadFingerprint({
    required StationAssessmentCreateInput content,
    required EastMalaysiaSiteValidationResult validationResult,
  }) {
    final candidate = validationResult.candidate;

    // Keep this order aligned with the validated-create RPC's material input
    // order. Listing every field explicitly makes retry identity independent
    // of Map insertion order and excludes server-derived validation state.
    return jsonEncode(<Object?>[
      content.locationName,
      content.populationDensity,
      content.trafficLevel,
      content.registeredVehicleCount,
      content.nearbyFuelStations,
      content.competitorDistanceKm,
      content.roadAccessibility,
      content.commercialActivity,
      content.residentialActivity,
      content.landAccessibility,
      content.finalScore,
      content.suitabilityCategory,
      content.recommendation,
      content.explanation,
      candidate.point.latitude,
      candidate.point.longitude,
      candidate.analysisRadiusKm,
      validationResult.boundaryDatasetId,
    ]);
  }
}
