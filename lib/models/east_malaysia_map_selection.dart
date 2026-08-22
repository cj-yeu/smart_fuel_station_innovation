import 'east_malaysia_site_validation_result.dart';
import 'nearby_fuel_station_result.dart';

/// A confirmed authoritative site validation plus optional public OSM context.
///
/// A station-data outage must not weaken or invalidate an authoritative inside
/// result, so [nearbyFuelStations] is intentionally nullable.
class EastMalaysiaMapSelection {
  final EastMalaysiaSiteValidationResult validationResult;
  final NearbyFuelStationResult? nearbyFuelStations;

  const EastMalaysiaMapSelection({
    required this.validationResult,
    this.nearbyFuelStations,
  });
}
