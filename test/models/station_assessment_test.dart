import 'package:flutter_test/flutter_test.dart';
import 'package:smart_fuell_station_innovation/models/station_assessment.dart';

void main() {
  group('StationAssessment.fromMap', () {
    test('parses every existing field with a non-null company_id', () {
      final assessment = StationAssessment.fromMap({
        ...assessmentRow(),
        'company_id': '10000000-0000-0000-0000-000000000001',
      });

      expect(assessment.id, '30000000-0000-0000-0000-000000000001');
      expect(assessment.userId, '20000000-0000-0000-0000-000000000001');
      expect(assessment.companyId, '10000000-0000-0000-0000-000000000001');
      expect(assessment.locationName, 'Kota Kinabalu test site');
      expect(assessment.populationDensity, 1234.5);
      expect(assessment.trafficLevel, 4);
      expect(assessment.registeredVehicleCount, 25000);
      expect(assessment.nearbyFuelStations, 2);
      expect(assessment.competitorDistanceKm, 4.25);
      expect(assessment.roadAccessibility, 5);
      expect(assessment.commercialActivity, 4);
      expect(assessment.residentialActivity, 3);
      expect(assessment.landAccessibility, 2);
      expect(assessment.finalScore, 72.3);
      expect(assessment.suitabilityCategory, 'Good');
      expect(assessment.recommendation, 'Test recommendation');
      expect(assessment.explanation, 'Test explanation');
      expect(assessment.createdAt, DateTime.parse('2026-08-16T01:02:03.000Z'));
      expect(assessment.updatedAt, DateTime.parse('2026-08-16T04:05:06.000Z'));
    });

    test('parses a legacy row with a null company_id', () {
      final assessment = StationAssessment.fromMap({
        ...assessmentRow(),
        'company_id': null,
      });

      expect(assessment.companyId, isNull);
      expect(assessment.locationName, 'Kota Kinabalu test site');
      expect(assessment.finalScore, 72.3);
    });

    test('parses a legacy-shaped row with no company_id key', () {
      final assessment = StationAssessment.fromMap(assessmentRow());

      expect(assessment.companyId, isNull);
      expect(assessment.userId, '20000000-0000-0000-0000-000000000001');
      expect(assessment.createdAt, isA<DateTime>());
    });
  });
}

Map<String, dynamic> assessmentRow() {
  return {
    'id': '30000000-0000-0000-0000-000000000001',
    'user_id': '20000000-0000-0000-0000-000000000001',
    'location_name': 'Kota Kinabalu test site',
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
    'recommendation': 'Test recommendation',
    'explanation': 'Test explanation',
    'created_at': '2026-08-16T01:02:03.000Z',
    'updated_at': '2026-08-16T04:05:06.000Z',
  };
}
