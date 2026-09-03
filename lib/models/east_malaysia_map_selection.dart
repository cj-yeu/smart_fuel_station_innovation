import 'east_malaysia_site_validation_result.dart';
import 'nearby_fuel_station_result.dart';
import 'site_factor_intelligence_result.dart';

class EastMalaysiaMapSelection {
  final EastMalaysiaSiteValidationResult validationResult;
  final NearbyFuelStationResult? nearbyFuelStations;
  final SiteFactorIntelligenceResult? siteFactorIntelligence;

  const EastMalaysiaMapSelection({
    required this.validationResult,
    this.nearbyFuelStations,
    this.siteFactorIntelligence,
  });
}
