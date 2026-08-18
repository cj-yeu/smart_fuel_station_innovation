import 'package:flutter_test/flutter_test.dart';
import 'package:smart_fuell_station_innovation/models/east_malaysia_site_validation_result.dart';
import 'package:smart_fuell_station_innovation/models/east_malaysia_territory.dart';
import 'package:smart_fuell_station_innovation/models/geo_point.dart';
import 'package:smart_fuell_station_innovation/models/station_assessment_create_input.dart';
import 'package:smart_fuell_station_innovation/models/station_assessment_validated_create_input.dart';

void main() {
  test('serializes exact content and candidate RPC parameters', () {
    final input = StationAssessmentValidatedCreateInput(
      content: contentInput,
      validationResult: insideResult,
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
    });
  });

  test('never serializes authoritative ownership or geography results', () {
    final params = StationAssessmentValidatedCreateInput(
      content: contentInput,
      validationResult: insideResult,
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
      ),
      throwsArgumentError,
    );
  });
}

const datasetId = 'de8b4433-7315-5e60-8195-1d76744765eb';

final insideResult = EastMalaysiaSiteValidationResult.fromRpcRow(
  row: {
    'validation_status': 'inside',
    'confirmed_territory': EastMalaysiaTerritory.sabah.storageValue,
    'boundary_dataset_id': datasetId,
  },
  point: GeoPoint(latitude: 5.9804, longitude: 116.0735),
  analysisRadiusKm: 5,
);

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
