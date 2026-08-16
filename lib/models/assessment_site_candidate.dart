import 'east_malaysia_territory.dart';
import 'geo_point.dart';

enum GeographicValidationStatus {
  unverified,
  inside,
  outside,
  boundaryReviewRequired,
}

class AssessmentSiteCandidate {
  static const supportedAnalysisRadiiKm = <double>[3, 5, 10];

  final GeoPoint point;
  final double analysisRadiusKm;
  final GeographicValidationStatus validationStatus;
  final EastMalaysiaTerritory? confirmedTerritory;

  AssessmentSiteCandidate({
    required this.point,
    required this.analysisRadiusKm,
    required this.validationStatus,
    this.confirmedTerritory,
  }) {
    if (!analysisRadiusKm.isFinite ||
        !supportedAnalysisRadiiKm.contains(analysisRadiusKm)) {
      throw ArgumentError.value(
        analysisRadiusKm,
        'analysisRadiusKm',
        'Analysis radius must be exactly 3, 5, or 10 kilometres.',
      );
    }

    if (validationStatus == GeographicValidationStatus.inside &&
        confirmedTerritory == null) {
      throw ArgumentError(
        'An inside candidate requires a confirmed East Malaysia territory.',
      );
    }

    if (validationStatus != GeographicValidationStatus.inside &&
        confirmedTerritory != null) {
      throw ArgumentError(
        'Only an inside candidate may have a confirmed East Malaysia territory.',
      );
    }
  }

  bool get isValidatedInside =>
      validationStatus == GeographicValidationStatus.inside;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is AssessmentSiteCandidate &&
            point == other.point &&
            analysisRadiusKm == other.analysisRadiusKm &&
            validationStatus == other.validationStatus &&
            confirmedTerritory == other.confirmedTerritory;
  }

  @override
  int get hashCode => Object.hash(
    point,
    analysisRadiusKm,
    validationStatus,
    confirmedTerritory,
  );

  @override
  String toString() {
    return 'AssessmentSiteCandidate('
        'point: $point, '
        'analysisRadiusKm: $analysisRadiusKm, '
        'validationStatus: $validationStatus, '
        'confirmedTerritory: $confirmedTerritory)';
  }
}
