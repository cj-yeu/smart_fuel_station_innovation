class StationAssessmentCreateInput {
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

  const StationAssessmentCreateInput({
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
  });

  Map<String, dynamic> toInsertMap() {
    return {
      'location_name': locationName,
      'population_density': populationDensity,
      'traffic_level': trafficLevel,
      'registered_vehicle_count': registeredVehicleCount,
      'nearby_fuel_stations': nearbyFuelStations,
      'competitor_distance_km': competitorDistanceKm,
      'road_accessibility': roadAccessibility,
      'commercial_activity': commercialActivity,
      'residential_activity': residentialActivity,
      'land_accessibility': landAccessibility,
      'final_score': finalScore,
      'suitability_category': suitabilityCategory,
      'recommendation': recommendation,
      'explanation': explanation,
    };
  }
}
