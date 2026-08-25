class AssessmentDraft {
  final String locationName;
  final String populationDensity;
  final String registeredVehicleCount;
  final String nearbyFuelStations;
  final String competitorDistanceKm;
  final int trafficLevel;
  final int roadAccessibility;
  final int commercialActivity;
  final int residentialActivity;
  final int landAccessibility;
  final DateTime updatedAt;

  const AssessmentDraft({
    required this.locationName,
    required this.populationDensity,
    required this.registeredVehicleCount,
    required this.nearbyFuelStations,
    required this.competitorDistanceKm,
    required this.trafficLevel,
    required this.roadAccessibility,
    required this.commercialActivity,
    required this.residentialActivity,
    required this.landAccessibility,
    required this.updatedAt,
  });

  bool get hasContent =>
      locationName.trim().isNotEmpty ||
      populationDensity.trim().isNotEmpty ||
      registeredVehicleCount.trim().isNotEmpty ||
      nearbyFuelStations.trim().isNotEmpty ||
      competitorDistanceKm.trim().isNotEmpty ||
      trafficLevel != 3 ||
      roadAccessibility != 3 ||
      commercialActivity != 3 ||
      residentialActivity != 3 ||
      landAccessibility != 3;

  Map<String, Object?> toDatabaseRow({required String userId}) => {
    'user_id': userId,
    'location_name': locationName,
    'population_density': populationDensity,
    'registered_vehicle_count': registeredVehicleCount,
    'nearby_fuel_stations': nearbyFuelStations,
    'competitor_distance_km': competitorDistanceKm,
    'traffic_level': trafficLevel,
    'road_accessibility': roadAccessibility,
    'commercial_activity': commercialActivity,
    'residential_activity': residentialActivity,
    'land_accessibility': landAccessibility,
    'updated_at_ms': updatedAt.millisecondsSinceEpoch,
  };

  factory AssessmentDraft.fromDatabaseRow(Map<String, Object?> row) {
    return AssessmentDraft(
      locationName: _string(row['location_name']),
      populationDensity: _string(row['population_density']),
      registeredVehicleCount: _string(row['registered_vehicle_count']),
      nearbyFuelStations: _string(row['nearby_fuel_stations']),
      competitorDistanceKm: _string(row['competitor_distance_km']),
      trafficLevel: _rating(row['traffic_level']),
      roadAccessibility: _rating(row['road_accessibility']),
      commercialActivity: _rating(row['commercial_activity']),
      residentialActivity: _rating(row['residential_activity']),
      landAccessibility: _rating(row['land_accessibility']),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        _integer(row['updated_at_ms']),
      ),
    );
  }

  static String _string(Object? value) => value is String ? value : '';

  static int _integer(Object? value) => value is int ? value : 0;

  static int _rating(Object? value) {
    final rating = _integer(value);
    return rating >= 1 && rating <= 5 ? rating : 3;
  }
}
