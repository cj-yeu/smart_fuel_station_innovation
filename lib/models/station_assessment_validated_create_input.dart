import 'east_malaysia_site_validation_result.dart';
import 'station_assessment_create_input.dart';

class StationAssessmentValidatedCreateInput {
  final StationAssessmentCreateInput content;
  final EastMalaysiaSiteValidationResult validationResult;

  StationAssessmentValidatedCreateInput({
    required this.content,
    required this.validationResult,
  }) {
    if (!validationResult.candidate.isValidatedInside ||
        validationResult.boundaryDatasetId == null) {
      throw ArgumentError(
        'Validated assessment creation requires an authoritative inside result '
        'with boundary dataset provenance.',
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
    };
  }
}
