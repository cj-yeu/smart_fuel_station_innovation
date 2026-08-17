import 'assessment_site_candidate.dart';
import 'east_malaysia_territory.dart';
import 'geo_point.dart';

class EastMalaysiaSiteValidationResult {
  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  final AssessmentSiteCandidate candidate;
  final String? boundaryDatasetId;

  const EastMalaysiaSiteValidationResult._({
    required this.candidate,
    required this.boundaryDatasetId,
  });

  factory EastMalaysiaSiteValidationResult.fromRpcRow({
    required Map<String, dynamic> row,
    required GeoPoint point,
    required double analysisRadiusKm,
  }) {
    final status = _parseStatus(row['validation_status']);
    final territory = _parseTerritory(row['confirmed_territory']);
    final boundaryDatasetId = _parseBoundaryDatasetId(
      row['boundary_dataset_id'],
    );

    switch (status) {
      case GeographicValidationStatus.unverified:
        if (territory != null || boundaryDatasetId != null) {
          throw const FormatException(
            'An unverified result cannot contain a confirmed territory or '
            'boundary dataset ID.',
          );
        }
      case GeographicValidationStatus.inside:
        if (territory == null || boundaryDatasetId == null) {
          throw const FormatException(
            'An inside result requires a confirmed territory and boundary '
            'dataset ID.',
          );
        }
      case GeographicValidationStatus.outside:
      case GeographicValidationStatus.boundaryReviewRequired:
        if (territory != null || boundaryDatasetId == null) {
          throw const FormatException(
            'A non-inside validated result requires a boundary dataset ID and '
            'cannot contain a confirmed territory.',
          );
        }
    }

    return EastMalaysiaSiteValidationResult._(
      candidate: AssessmentSiteCandidate(
        point: point,
        analysisRadiusKm: analysisRadiusKm,
        validationStatus: status,
        confirmedTerritory: territory,
      ),
      boundaryDatasetId: boundaryDatasetId,
    );
  }

  static GeographicValidationStatus _parseStatus(Object? value) {
    return switch (value) {
      'unverified' => GeographicValidationStatus.unverified,
      'inside' => GeographicValidationStatus.inside,
      'outside' => GeographicValidationStatus.outside,
      'boundary_review_required' =>
        GeographicValidationStatus.boundaryReviewRequired,
      _ => throw FormatException(
        'Unknown or missing geographic validation status: $value',
      ),
    };
  }

  static EastMalaysiaTerritory? _parseTerritory(Object? value) {
    if (value == null) return null;
    if (value is! String) {
      throw const FormatException(
        'Confirmed territory must be a valid East Malaysia territory value.',
      );
    }

    try {
      return EastMalaysiaTerritory.fromStorageValue(value);
    } on ArgumentError {
      throw FormatException('Unknown East Malaysia territory: $value');
    }
  }

  static String? _parseBoundaryDatasetId(Object? value) {
    if (value == null) return null;
    if (value is! String || !_uuidPattern.hasMatch(value)) {
      throw const FormatException('Boundary dataset ID must be a valid UUID.');
    }
    return value;
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is EastMalaysiaSiteValidationResult &&
            candidate == other.candidate &&
            boundaryDatasetId == other.boundaryDatasetId;
  }

  @override
  int get hashCode => Object.hash(candidate, boundaryDatasetId);

  @override
  String toString() {
    return 'EastMalaysiaSiteValidationResult('
        'candidate: $candidate, '
        'boundaryDatasetId: $boundaryDatasetId)';
  }
}
