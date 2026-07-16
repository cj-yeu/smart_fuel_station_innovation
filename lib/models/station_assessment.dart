class StationAssessment {
  final String id;
  final String userId;
  final String locationName;
  final double populationDensity;
  final int trafficLevel;
  final int registeredVehicleCount;
  final int nearbyFuelStations;
  final double competitorDistanceKm;
  final int roadAccessibility;
  final int commercialActivity;
  final int residentialActivity;
  final int landAccessibility;
  final double finalScore;
  final String suitabilityCategory;
  final String recommendation;
  final String explanation;
  final DateTime createdAt;
  final DateTime updatedAt;

  const StationAssessment({
    required this.id,
    required this.userId,
    required this.locationName,
    required this.populationDensity,
    required this.trafficLevel,
    required this.registeredVehicleCount,
    required this.nearbyFuelStations,
    required this.competitorDistanceKm,
    required this.roadAccessibility,
    required this.commercialActivity,
    required this.residentialActivity,
    required this.landAccessibility,
    required this.finalScore,
    required this.suitabilityCategory,
    required this.recommendation,
    required this.explanation,
    required this.createdAt,
    required this.updatedAt,
  });

  factory StationAssessment.fromMap(Map<String, dynamic> map) {
    return StationAssessment(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      locationName: map['location_name'] as String,
      populationDensity:
      (map['population_density'] as num).toDouble(),
      trafficLevel: map['traffic_level'] as int,
      registeredVehicleCount:
      map['registered_vehicle_count'] as int,
      nearbyFuelStations: map['nearby_fuel_stations'] as int,
      competitorDistanceKm:
      (map['competitor_distance_km'] as num).toDouble(),
      roadAccessibility: map['road_accessibility'] as int,
      commercialActivity: map['commercial_activity'] as int,
      residentialActivity: map['residential_activity'] as int,
      landAccessibility: map['land_accessibility'] as int,
      finalScore: (map['final_score'] as num).toDouble(),
      suitabilityCategory: map['suitability_category'] as String,
      recommendation: map['recommendation'] as String,
      explanation: map['explanation'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}