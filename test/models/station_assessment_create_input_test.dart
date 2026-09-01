import 'package:flutter_test/flutter_test.dart';
import 'package:smart_fuel_station_innovation/models/station_assessment_create_input.dart';

void main() {
  group('StationAssessmentCreateInput.toInsertMap', () {
    test('serializes every content field with its database column name', () {
      const input = StationAssessmentCreateInput(
        locationName: 'Kota Kinabalu test site',
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
        recommendation: 'Test recommendation',
        explanation: 'Test explanation',
      );

      expect(input.toInsertMap(), {
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
      });
    });

    test('preserves numeric types and values', () {
      final map = createInput.toInsertMap();

      expect(map['population_density'], isA<double>());
      expect(map['population_density'], 1234.5);
      expect(map['traffic_level'], isA<int>());
      expect(map['traffic_level'], 4);
      expect(map['registered_vehicle_count'], isA<int>());
      expect(map['registered_vehicle_count'], 25000);
      expect(map['nearby_fuel_stations'], isA<int>());
      expect(map['nearby_fuel_stations'], 2);
      expect(map['competitor_distance_km'], isA<double>());
      expect(map['competitor_distance_km'], 4.25);
      expect(map['road_accessibility'], isA<int>());
      expect(map['commercial_activity'], isA<int>());
      expect(map['residential_activity'], isA<int>());
      expect(map['land_accessibility'], isA<int>());
      expect(map['final_score'], isA<double>());
      expect(map['final_score'], 72.3);
    });

    test('cannot serialize identity, ownership, or audit columns', () {
      final map = createInput.toInsertMap();

      expect(map, isNot(contains('id')));
      expect(map, isNot(contains('user_id')));
      expect(map, isNot(contains('company_id')));
      expect(map, isNot(contains('created_at')));
      expect(map, isNot(contains('updated_at')));
    });
  });
}

const createInput = StationAssessmentCreateInput(
  locationName: 'Kota Kinabalu test site',
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
  recommendation: 'Test recommendation',
  explanation: 'Test explanation',
);
