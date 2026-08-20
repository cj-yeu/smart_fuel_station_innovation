import 'package:flutter_test/flutter_test.dart';
import 'package:smart_fuell_station_innovation/models/east_malaysia_site_validation_result.dart';
import 'package:smart_fuell_station_innovation/models/geo_point.dart';
import 'package:smart_fuell_station_innovation/models/station_assessment_create_input.dart';
import 'package:smart_fuell_station_innovation/models/station_assessment_validated_create_input.dart';
import 'package:smart_fuell_station_innovation/services/station_assessment_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('createValidatedAssessment', () {
    test('calls exact RPC payload and verifies the RLS-fetched row', () async {
      String? rpcName;
      Map<String, dynamic>? rpcParams;
      String? loadedId;
      final repository = testRepository(
        rpc: (name, params) async {
          rpcName = name;
          rpcParams = params;
          return assessmentId;
        },
        loader: (id) async {
          loadedId = id;
          return [validatedAssessmentRow()];
        },
      );

      final assessment = await repository.createValidatedAssessment(
        validatedInput(),
      );

      expect(rpcName, 'create_validated_station_assessment');
      expect(rpcParams, validatedInput().toRpcParams());
      expect(loadedId, assessmentId);
      expect(assessment.id, assessmentId);
      expect(assessment.userId, userId);
      expect(assessment.confirmedTerritory?.storageValue, 'sabah');
      expect(
        assessment.siteLocation,
        GeoPoint(latitude: 5.9804, longitude: 116.0735),
      );
      expect(assessment.validatedCreateRequestId, requestId);
    });

    for (final malformed in <Object?>[
      null,
      '',
      'not-a-uuid',
      <String>[assessmentId, secondAssessmentId],
    ]) {
      test('rejects malformed or non-scalar RPC result $malformed', () async {
        var loaderCalled = false;
        final repository = testRepository(
          rpc: (_, _) async => malformed,
          loader: (_) async {
            loaderCalled = true;
            return [validatedAssessmentRow()];
          },
        );

        await expectLater(
          repository.createValidatedAssessment(validatedInput()),
          throwsStateError,
        );
        expect(loaderCalled, isFalse);
      });
    }

    test('rejects missing or multiple RLS-fetched rows', () async {
      for (final rows in <List<Map<String, dynamic>>>[
        const [],
        [validatedAssessmentRow(), validatedAssessmentRow()],
      ]) {
        final repository = testRepository(
          rpc: (_, _) async => assessmentId,
          loader: (_) async => rows,
        );
        await expectLater(
          repository.createValidatedAssessment(validatedInput()),
          throwsStateError,
        );
      }
    });

    test('rejects a row whose creator differs from the session', () async {
      final repository = testRepository(
        rpc: (_, _) async => assessmentId,
        loader: (_) async => [
          validatedAssessmentRow()
            ..['user_id'] = '52000000-0000-0000-0000-000000000099',
        ],
      );

      await expectLater(
        repository.createValidatedAssessment(validatedInput()),
        throwsStateError,
      );
    });

    test('requires an authenticated user before calling the RPC', () async {
      var rpcCalled = false;
      final repository = StationAssessmentRepository(
        SupabaseClient('https://example.invalid', 'test-anon-key'),
        authenticatedUserIdProvider: () => null,
        validatedAssessmentRpcCaller: (_, _) async {
          rpcCalled = true;
          return assessmentId;
        },
        assessmentRowsByIdLoader: (_) async => [validatedAssessmentRow()],
      );

      await expectLater(
        repository.createValidatedAssessment(validatedInput()),
        throwsStateError,
      );
      expect(rpcCalled, isFalse);
    });
  });
}

StationAssessmentRepository testRepository({
  required ValidatedAssessmentRpcCaller rpc,
  required AssessmentRowsByIdLoader loader,
}) {
  return StationAssessmentRepository(
    SupabaseClient('https://example.invalid', 'test-anon-key'),
    authenticatedUserIdProvider: () => userId,
    validatedAssessmentRpcCaller: rpc,
    assessmentRowsByIdLoader: loader,
  );
}

StationAssessmentValidatedCreateInput validatedInput() {
  return StationAssessmentValidatedCreateInput(
    content: contentInput,
    validationResult: EastMalaysiaSiteValidationResult.fromRpcRow(
      row: {
        'validation_status': 'inside',
        'confirmed_territory': 'sabah',
        'boundary_dataset_id': datasetId,
      },
      point: GeoPoint(latitude: 5.9804, longitude: 116.0735),
      analysisRadiusKm: 5,
    ),
    requestId: requestId,
  );
}

Map<String, dynamic> validatedAssessmentRow() {
  return {
    'id': assessmentId,
    'user_id': userId,
    'company_id': companyId,
    'location_name': 'Validated Sabah site',
    'population_density': 1234.5,
    'traffic_level': 4,
    'registered_vehicle_count': 25000,
    'nearby_fuel_stations': 2,
    'competitor_distance_km': 4.25,
    'road_accessibility': 5,
    'commercial_activity': 4,
    'residential_activity': 3,
    'land_accessibility': 2,
    'final_score': 72.3,
    'suitability_category': 'Good',
    'recommendation': 'Recommendation',
    'explanation': 'Explanation',
    'site_location': '0101000020E610000062105839B4045D405DFE43FAEDEB1740',
    'analysis_radius_km': 5,
    'geographic_validation_status': 'inside',
    'confirmed_territory': 'sabah',
    'boundary_dataset_id': datasetId,
    'geographically_validated_at': '2026-08-18T01:02:03.000Z',
    'validated_create_request_id': requestId,
    'created_at': '2026-08-18T01:02:03.000Z',
    'updated_at': '2026-08-18T01:02:03.000Z',
  };
}

const userId = '52000000-0000-0000-0000-000000000001';
const companyId = '51000000-0000-0000-0000-000000000001';
const assessmentId = '53000000-0000-0000-0000-000000000001';
const secondAssessmentId = '53000000-0000-0000-0000-000000000002';
const datasetId = 'de8b4433-7315-5e60-8195-1d76744765eb';
const requestId = '73000000-0000-0000-0000-000000000001';

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
