import 'package:flutter_test/flutter_test.dart';
import 'package:smart_fuel_station_innovation/models/east_malaysia_site_validation_result.dart';
import 'package:smart_fuel_station_innovation/models/east_malaysia_territory.dart';
import 'package:smart_fuel_station_innovation/models/geo_point.dart';
import 'package:smart_fuel_station_innovation/models/station_assessment_create_input.dart';
import 'package:smart_fuel_station_innovation/models/station_assessment_validated_create_input.dart';

void main() {
  test('serializes exact content and candidate RPC parameters', () {
    final input = StationAssessmentValidatedCreateInput(
      content: contentInput,
      validationResult: insideResult,
      requestId: requestId,
    );

    expect(input.toRpcParams(), {
      'p_location_name': 'Validated Sabah site',
      'p_population_density': 1234.5,
      'p_traffic_level': 4,
      'p_registered_vehicle_count': 25000,
      'p_nearby_fuel_stations': 2,
      'p_competitor_distance_km': 4.25,
      'p_road_accessibility': 5,
      'p_commercial_activity': 4,
      'p_residential_activity': 3,
      'p_land_accessibility': 2,
      'p_final_score': 72.3,
      'p_suitability_category': 'Good',
      'p_recommendation': 'Recommendation',
      'p_explanation': 'Explanation',
      'p_latitude': 5.9804,
      'p_longitude': 116.0735,
      'p_analysis_radius_km': 5,
      'p_expected_boundary_dataset_id': datasetId,
      'p_request_id': requestId,
    });
  });

  test('never serializes authoritative ownership or geography results', () {
    final params = StationAssessmentValidatedCreateInput(
      content: contentInput,
      validationResult: insideResult,
      requestId: requestId,
    ).toRpcParams();

    for (final forbidden in <String>[
      'user_id',
      'company_id',
      'confirmed_territory',
      'geographic_validation_status',
      'geographically_validated_at',
      'p_user_id',
      'p_company_id',
      'p_confirmed_territory',
      'p_geographic_validation_status',
      'p_geographically_validated_at',
    ]) {
      expect(params, isNot(contains(forbidden)));
    }
  });

  test('rejects a result that is not authoritatively inside', () {
    final unverified = EastMalaysiaSiteValidationResult.fromRpcRow(
      row: {
        'validation_status': 'unverified',
        'confirmed_territory': null,
        'boundary_dataset_id': null,
      },
      point: GeoPoint(latitude: 5.9804, longitude: 116.0735),
      analysisRadiusKm: 5,
    );

    expect(
      () => StationAssessmentValidatedCreateInput(
        content: contentInput,
        validationResult: unverified,
        requestId: requestId,
      ),
      throwsArgumentError,
    );
  });

  test('rejects a malformed request ID', () {
    expect(
      () => StationAssessmentValidatedCreateInput(
        content: contentInput,
        validationResult: insideResult,
        requestId: 'not-a-uuid',
      ),
      throwsArgumentError,
    );
  });

  group('payload fingerprint', () {
    test('is stable for reconstructed input and excludes the request ID', () {
      final first = fingerprint();
      final reconstructed = fingerprint(
        content: createContentInput(),
        validationResult: createInsideResult(),
      );

      expect(reconstructed, first);
      expect(first, isNot(contains(requestId)));
    });

    final changedContentCases = <String, StationAssessmentCreateInput>{
      'locationName': createContentInput(locationName: 'Changed site'),
      'populationDensity': createContentInput(populationDensity: 1234.6),
      'trafficLevel': createContentInput(trafficLevel: 5),
      'registeredVehicleCount': createContentInput(
        registeredVehicleCount: 25001,
      ),
      'nearbyFuelStations': createContentInput(nearbyFuelStations: 3),
      'competitorDistanceKm': createContentInput(competitorDistanceKm: 4.5),
      'roadAccessibility': createContentInput(roadAccessibility: 4),
      'commercialActivity': createContentInput(commercialActivity: 3),
      'residentialActivity': createContentInput(residentialActivity: 2),
      'landAccessibility': createContentInput(landAccessibility: 1),
      'finalScore': createContentInput(finalScore: 72.4),
      'suitabilityCategory': createContentInput(
        suitabilityCategory: 'Excellent',
      ),
      'recommendation': createContentInput(recommendation: 'Changed'),
      'explanation': createContentInput(explanation: 'Changed'),
    };

    for (final entry in changedContentCases.entries) {
      test('${entry.key} changes the fingerprint', () {
        expect(fingerprint(content: entry.value), isNot(fingerprint()));
      });
    }

    final changedGeographyCases = <String, EastMalaysiaSiteValidationResult>{
      'latitude': createInsideResult(latitude: 5.9805),
      'longitude': createInsideResult(longitude: 116.0736),
      'analysis radius': createInsideResult(analysisRadiusKm: 10),
      'boundary dataset UUID': createInsideResult(
        boundaryDatasetId: 'de8b4433-7315-5e60-8195-1d76744765ec',
      ),
    };

    for (final entry in changedGeographyCases.entries) {
      test('${entry.key} changes the fingerprint', () {
        expect(
          fingerprint(validationResult: entry.value),
          isNot(fingerprint()),
        );
      });
    }
  });
}

const datasetId = 'de8b4433-7315-5e60-8195-1d76744765eb';
const requestId = '73000000-0000-0000-0000-000000000001';

final insideResult = EastMalaysiaSiteValidationResult.fromRpcRow(
  row: {
    'validation_status': 'inside',
    'confirmed_territory': EastMalaysiaTerritory.sabah.storageValue,
    'boundary_dataset_id': datasetId,
  },
  point: GeoPoint(latitude: 5.9804, longitude: 116.0735),
  analysisRadiusKm: 5,
);

String fingerprint({
  StationAssessmentCreateInput? content,
  EastMalaysiaSiteValidationResult? validationResult,
}) {
  return StationAssessmentValidatedCreateInput.payloadFingerprint(
    content: content ?? contentInput,
    validationResult: validationResult ?? insideResult,
  );
}

EastMalaysiaSiteValidationResult createInsideResult({
  double latitude = 5.9804,
  double longitude = 116.0735,
  double analysisRadiusKm = 5,
  String boundaryDatasetId = datasetId,
}) {
  return EastMalaysiaSiteValidationResult.fromRpcRow(
    row: {
      'validation_status': 'inside',
      'confirmed_territory': EastMalaysiaTerritory.sabah.storageValue,
      'boundary_dataset_id': boundaryDatasetId,
    },
    point: GeoPoint(latitude: latitude, longitude: longitude),
    analysisRadiusKm: analysisRadiusKm,
  );
}

StationAssessmentCreateInput createContentInput({
  String locationName = 'Validated Sabah site',
  double populationDensity = 1234.5,
  int trafficLevel = 4,
  int registeredVehicleCount = 25000,
  int nearbyFuelStations = 2,
  double competitorDistanceKm = 4.25,
  int roadAccessibility = 5,
  int commercialActivity = 4,
  int residentialActivity = 3,
  int landAccessibility = 2,
  double finalScore = 72.3,
  String suitabilityCategory = 'Good',
  String recommendation = 'Recommendation',
  String explanation = 'Explanation',
}) {
  return StationAssessmentCreateInput(
    locationName: locationName,
    populationDensity: populationDensity,
    trafficLevel: trafficLevel,
    registeredVehicleCount: registeredVehicleCount,
    nearbyFuelStations: nearbyFuelStations,
    competitorDistanceKm: competitorDistanceKm,
    roadAccessibility: roadAccessibility,
    commercialActivity: commercialActivity,
    residentialActivity: residentialActivity,
    landAccessibility: landAccessibility,
    finalScore: finalScore,
    suitabilityCategory: suitabilityCategory,
    recommendation: recommendation,
    explanation: explanation,
  );
}

const contentInput = StationAssessmentCreateInput(
  locationName: 'Validated Sabah site',
  populationDensity: 1234.5,
  trafficLevel: 4,
  registeredVehicleCount: 25000,
  nearbyFuelStations: 2,
  competitorDistanceKm: 4.25,
  roadAccessibility: 5,
  commercialActivity: 4,
  residentialActivity: 3,
  landAccessibility: 2,
  finalScore: 72.3,
  suitabilityCategory: 'Good',
  recommendation: 'Recommendation',
  explanation: 'Explanation',
);
