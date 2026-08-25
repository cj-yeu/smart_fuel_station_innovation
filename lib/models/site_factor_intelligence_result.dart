import 'assessment_site_candidate.dart';
import 'geo_point.dart';

enum SiteFactorConfidence { medium, low }

class SiteFactorAttribution {
  final String source;
  final String url;
  final String licence;

  const SiteFactorAttribution({
    required this.source,
    required this.url,
    required this.licence,
  });

  factory SiteFactorAttribution.fromMap(Map<String, dynamic> map) {
    return SiteFactorAttribution(
      source: SiteFactorIntelligenceResult._requiredString(
        map['source'],
        'attribution source',
      ),
      url: SiteFactorIntelligenceResult._requiredString(
        map['url'],
        'attribution URL',
      ),
      licence: SiteFactorIntelligenceResult._requiredString(
        map['licence'],
        'attribution licence',
      ),
    );
  }
}

class DistrictReference {
  final String name;
  final String source;
  final String sourceUrl;
  final String licence;

  const DistrictReference({
    required this.name,
    required this.source,
    required this.sourceUrl,
    required this.licence,
  });

  factory DistrictReference.fromMap(Map<String, dynamic> map) {
    return DistrictReference(
      name: SiteFactorIntelligenceResult._requiredString(
        map['name'],
        'district name',
      ),
      source: SiteFactorIntelligenceResult._requiredString(
        map['source'],
        'district source',
      ),
      sourceUrl: SiteFactorIntelligenceResult._requiredString(
        map['source_url'],
        'district source URL',
      ),
      licence: SiteFactorIntelligenceResult._requiredString(
        map['licence'],
        'district licence',
      ),
    );
  }
}

class PopulationEvidence {
  final bool available;
  final double? estimatedPopulation;
  final double? densityPerSqKm;
  final int? suggestedLevel;
  final String? source;
  final int? dataYear;
  final SiteFactorConfidence confidence;

  const PopulationEvidence({
    required this.available,
    required this.estimatedPopulation,
    required this.densityPerSqKm,
    required this.suggestedLevel,
    required this.source,
    required this.dataYear,
    required this.confidence,
  });

  bool get hasUsableSuggestion =>
      available && densityPerSqKm != null && densityPerSqKm!.isFinite;
}

class RoadAccessibilityEvidence {
  final bool available;
  final double? nearestUsableRoadM;
  final int? majorRoadCount;
  final int? suggestedScore;
  final String? source;
  final DateTime? fetchedAt;
  final SiteFactorConfidence confidence;

  const RoadAccessibilityEvidence({
    required this.available,
    required this.nearestUsableRoadM,
    required this.majorRoadCount,
    required this.suggestedScore,
    required this.source,
    required this.fetchedAt,
    required this.confidence,
  });

  bool get hasUsableSuggestion =>
      available && suggestedScore != null && _isScore(suggestedScore!);
}

class CommercialActivityEvidence {
  final bool available;
  final int? commercialPoiCount;
  final int? commercialLanduseCount;
  final int? suggestedScore;
  final String? source;
  final DateTime? fetchedAt;
  final SiteFactorConfidence confidence;

  const CommercialActivityEvidence({
    required this.available,
    required this.commercialPoiCount,
    required this.commercialLanduseCount,
    required this.suggestedScore,
    required this.source,
    required this.fetchedAt,
    required this.confidence,
  });

  bool get hasUsableSuggestion =>
      available && suggestedScore != null && _isScore(suggestedScore!);
}

class ResidentialActivityEvidence {
  final bool available;
  final int? residentialFeatureCount;
  final int? residentialLanduseCount;
  final int? suggestedScore;
  final String? source;
  final DateTime? fetchedAt;
  final SiteFactorConfidence confidence;

  const ResidentialActivityEvidence({
    required this.available,
    required this.residentialFeatureCount,
    required this.residentialLanduseCount,
    required this.suggestedScore,
    required this.source,
    required this.fetchedAt,
    required this.confidence,
  });

  bool get hasUsableSuggestion =>
      available && suggestedScore != null && _isScore(suggestedScore!);
}

class LandAccessibilityEvidence {
  final bool available;
  final double? nearestAccessRoadM;
  final int? restrictedAccessFeatureCount;
  final int? suggestedScore;
  final String? source;
  final DateTime? fetchedAt;
  final SiteFactorConfidence confidence;

  const LandAccessibilityEvidence({
    required this.available,
    required this.nearestAccessRoadM,
    required this.restrictedAccessFeatureCount,
    required this.suggestedScore,
    required this.source,
    required this.fetchedAt,
    required this.confidence,
  });

  bool get hasUsableSuggestion =>
      available && suggestedScore != null && _isScore(suggestedScore!);
}

class VehicleDemandProxy {
  final bool available;
  final int? value;
  final String? geographicScope;
  final String? dataPeriod;
  final bool isProxy;
  final String? source;

  const VehicleDemandProxy({
    required this.available,
    required this.value,
    required this.geographicScope,
    required this.dataPeriod,
    required this.isProxy,
    required this.source,
  });

  bool get hasUsableSuggestion => available && value != null && value! >= 0;
}

class SiteFactorIntelligenceResult {
  final GeoPoint point;
  final double analysisRadiusKm;
  final DistrictReference? districtReference;
  final PopulationEvidence population;
  final RoadAccessibilityEvidence roadAccessibility;
  final CommercialActivityEvidence commercialActivity;
  final ResidentialActivityEvidence residentialActivity;
  final LandAccessibilityEvidence landAccessibility;
  final VehicleDemandProxy vehicleDemand;
  final List<SiteFactorAttribution> attribution;

  SiteFactorIntelligenceResult({
    required this.point,
    required this.analysisRadiusKm,
    required this.districtReference,
    required this.population,
    required this.roadAccessibility,
    required this.commercialActivity,
    required this.residentialActivity,
    required this.landAccessibility,
    required this.vehicleDemand,
    required List<SiteFactorAttribution> attribution,
  }) : attribution = List.unmodifiable(attribution) {
    if (!AssessmentSiteCandidate.supportedAnalysisRadiiKm.contains(
      analysisRadiusKm,
    )) {
      throw ArgumentError.value(
        analysisRadiusKm,
        'analysisRadiusKm',
        'Analysis radius must be exactly 3, 5, or 10 kilometres.',
      );
    }
  }

  factory SiteFactorIntelligenceResult.fromMap({
    required Map<String, dynamic> row,
    required GeoPoint expectedPoint,
    required double expectedAnalysisRadiusKm,
  }) {
    final candidate = _requiredMap(row['candidate'], 'candidate');
    final point = GeoPoint(
      latitude: _requiredDouble(candidate['latitude'], 'candidate latitude'),
      longitude: _requiredDouble(candidate['longitude'], 'candidate longitude'),
    );
    final radius = _requiredDouble(
      candidate['analysis_radius_km'],
      'candidate analysis radius',
    );
    if (!_sameCoordinate(point.latitude, expectedPoint.latitude) ||
        !_sameCoordinate(point.longitude, expectedPoint.longitude) ||
        radius != expectedAnalysisRadiusKm) {
      throw const FormatException(
        'Site-factor intelligence did not match the validated candidate.',
      );
    }

    final attributionValue = row['attribution'];
    if (attributionValue is! List) {
      throw const FormatException('Site-factor attribution must be a list.');
    }
    final attribution = attributionValue
        .map(
          (value) => SiteFactorAttribution.fromMap(
            _requiredMap(value, 'attribution entry'),
          ),
        )
        .toList(growable: false);

    return SiteFactorIntelligenceResult(
      point: point,
      analysisRadiusKm: radius,
      districtReference: _nullableDistrictReference(
        candidate['district_reference'],
      ),
      population: _parsePopulation(
        _requiredMap(row['population'], 'population'),
      ),
      roadAccessibility: _parseRoad(
        _requiredMap(row['road_accessibility'], 'road accessibility'),
      ),
      commercialActivity: _parseCommercial(
        _requiredMap(row['commercial_activity'], 'commercial activity'),
      ),
      residentialActivity: _parseResidential(
        _requiredMap(row['residential_activity'], 'residential activity'),
      ),
      landAccessibility: _parseLand(
        _requiredMap(row['land_accessibility'], 'land accessibility'),
      ),
      vehicleDemand: _parseVehicleDemand(
        _requiredMap(row['vehicle_demand'], 'vehicle demand'),
      ),
      attribution: attribution,
    );
  }

  static PopulationEvidence _parsePopulation(Map<String, dynamic> map) {
    final available = _requiredBool(
      map['available'],
      'population availability',
    );
    return PopulationEvidence(
      available: available,
      estimatedPopulation: _nullableDouble(
        map['estimated_population'],
        'estimated population',
      ),
      densityPerSqKm: _nullableDouble(
        map['density_per_sq_km'],
        'population density',
      ),
      suggestedLevel: _nullableScore(
        map['suggested_level'],
        'population level',
      ),
      source: _nullableString(map['source'], 'population source'),
      dataYear: _nullableInt(map['data_year'], 'population data year'),
      confidence: _parseConfidence(map['confidence']),
    );
  }

  static DistrictReference? _nullableDistrictReference(Object? value) {
    if (value == null) return null;
    return DistrictReference.fromMap(_requiredMap(value, 'district reference'));
  }

  static RoadAccessibilityEvidence _parseRoad(Map<String, dynamic> map) {
    return RoadAccessibilityEvidence(
      available: _requiredBool(map['available'], 'road availability'),
      nearestUsableRoadM: _nullableDouble(
        map['nearest_usable_road_m'],
        'nearest usable road distance',
      ),
      majorRoadCount: _nullableNonNegativeInt(
        map['major_road_count'],
        'major road count',
      ),
      suggestedScore: _nullableScore(map['suggested_score'], 'road score'),
      source: _nullableString(map['source'], 'road source'),
      fetchedAt: _nullableDateTime(map['fetched_at'], 'road fetched time'),
      confidence: _parseConfidence(map['confidence']),
    );
  }

  static CommercialActivityEvidence _parseCommercial(Map<String, dynamic> map) {
    return CommercialActivityEvidence(
      available: _requiredBool(map['available'], 'commercial availability'),
      commercialPoiCount: _nullableNonNegativeInt(
        map['commercial_poi_count'],
        'commercial POI count',
      ),
      commercialLanduseCount: _nullableNonNegativeInt(
        map['commercial_landuse_count'],
        'commercial land-use count',
      ),
      suggestedScore: _nullableScore(
        map['suggested_score'],
        'commercial score',
      ),
      source: _nullableString(map['source'], 'commercial source'),
      fetchedAt: _nullableDateTime(
        map['fetched_at'],
        'commercial fetched time',
      ),
      confidence: _parseConfidence(map['confidence']),
    );
  }

  static ResidentialActivityEvidence _parseResidential(
    Map<String, dynamic> map,
  ) {
    return ResidentialActivityEvidence(
      available: _requiredBool(map['available'], 'residential availability'),
      residentialFeatureCount: _nullableNonNegativeInt(
        map['residential_feature_count'],
        'residential feature count',
      ),
      residentialLanduseCount: _nullableNonNegativeInt(
        map['residential_landuse_count'],
        'residential land-use count',
      ),
      suggestedScore: _nullableScore(
        map['suggested_score'],
        'residential score',
      ),
      source: _nullableString(map['source'], 'residential source'),
      fetchedAt: _nullableDateTime(
        map['fetched_at'],
        'residential fetched time',
      ),
      confidence: _parseConfidence(map['confidence']),
    );
  }

  static LandAccessibilityEvidence _parseLand(Map<String, dynamic> map) {
    return LandAccessibilityEvidence(
      available: _requiredBool(map['available'], 'land availability'),
      nearestAccessRoadM: _nullableDouble(
        map['nearest_access_road_m'],
        'nearest access road distance',
      ),
      restrictedAccessFeatureCount: _nullableNonNegativeInt(
        map['restricted_access_feature_count'],
        'restricted access feature count',
      ),
      suggestedScore: _nullableScore(map['suggested_score'], 'land score'),
      source: _nullableString(map['source'], 'land source'),
      fetchedAt: _nullableDateTime(map['fetched_at'], 'land fetched time'),
      confidence: _parseConfidence(map['confidence']),
    );
  }

  static VehicleDemandProxy _parseVehicleDemand(Map<String, dynamic> map) {
    final value = _nullableNonNegativeInt(map['value'], 'vehicle demand value');
    return VehicleDemandProxy(
      available: _requiredBool(map['available'], 'vehicle demand availability'),
      value: value,
      geographicScope: _nullableString(
        map['geographic_scope'],
        'vehicle demand geographic scope',
      ),
      dataPeriod: _nullableString(map['data_period'], 'vehicle demand period'),
      isProxy: _requiredBool(map['is_proxy'], 'vehicle demand proxy flag'),
      source: _nullableString(map['source'], 'vehicle demand source'),
    );
  }

  static bool _sameCoordinate(double first, double second) =>
      first == second || (first == 0 && second == 0);

  static Map<String, dynamic> _requiredMap(Object? value, String fieldName) {
    if (value is Map) return Map<String, dynamic>.from(value);
    throw FormatException('Site-factor $fieldName is invalid.');
  }

  static bool _requiredBool(Object? value, String fieldName) {
    if (value is bool) return value;
    throw FormatException('Site-factor $fieldName must be a boolean.');
  }

  static String _requiredString(Object? value, String fieldName) {
    if (value is String && value.trim().isNotEmpty) return value;
    throw FormatException('Site-factor $fieldName must be a string.');
  }

  static String? _nullableString(Object? value, String fieldName) {
    if (value == null) return null;
    return _requiredString(value, fieldName);
  }

  static double _requiredDouble(Object? value, String fieldName) {
    if (value is num && value.toDouble().isFinite) return value.toDouble();
    throw FormatException('Site-factor $fieldName must be finite.');
  }

  static double? _nullableDouble(Object? value, String fieldName) {
    if (value == null) return null;
    return _requiredDouble(value, fieldName);
  }

  static int? _nullableInt(Object? value, String fieldName) {
    if (value == null) return null;
    if (value is int) return value;
    throw FormatException('Site-factor $fieldName must be an integer.');
  }

  static int? _nullableNonNegativeInt(Object? value, String fieldName) {
    final integer = _nullableInt(value, fieldName);
    if (integer == null || integer >= 0) return integer;
    throw FormatException('Site-factor $fieldName cannot be negative.');
  }

  static int? _nullableScore(Object? value, String fieldName) {
    final score = _nullableInt(value, fieldName);
    if (score == null || _isScore(score)) return score;
    throw FormatException('Site-factor $fieldName must be from 1 to 5.');
  }

  static DateTime? _nullableDateTime(Object? value, String fieldName) {
    if (value == null) return null;
    if (value is! String) {
      throw FormatException('Site-factor $fieldName is invalid.');
    }
    return DateTime.tryParse(value) ??
        (throw FormatException('Site-factor $fieldName is invalid.'));
  }

  static SiteFactorConfidence _parseConfidence(Object? value) {
    return switch (value) {
      'medium' => SiteFactorConfidence.medium,
      'low' => SiteFactorConfidence.low,
      _ => throw const FormatException('Site-factor confidence is invalid.'),
    };
  }
}

bool _isScore(int value) => value >= 1 && value <= 5;
