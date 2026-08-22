import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/east_malaysia_site_validation_result.dart';
import '../models/nearby_fuel_station_result.dart';

typedef NearbyFuelStationFunctionCaller =
    Future<dynamic> Function(String functionName, Map<String, dynamic> body);
typedef NearbyFuelStationSessionProvider = bool Function();

abstract class NearbyFuelStationRepository {
  static const functionName = 'nearby-fuel-stations';

  factory NearbyFuelStationRepository(
    SupabaseClient client, {
    NearbyFuelStationFunctionCaller? functionCaller,
    NearbyFuelStationSessionProvider? sessionProvider,
  }) => _NearbyFuelStationRepository(
    client,
    functionCaller,
    sessionProvider,
  );

  /// Loads public OSM fuel-station context for an already authoritative inside
  /// result. The Edge Function independently revalidates the caller and site;
  /// this client never supplies company membership or territory authority.
  Future<NearbyFuelStationResult> fetchForValidatedSite(
    EastMalaysiaSiteValidationResult validationResult,
  );
}

class _NearbyFuelStationRepository implements NearbyFuelStationRepository {
  final SupabaseClient _client;
  final NearbyFuelStationFunctionCaller? _functionCaller;
  final NearbyFuelStationSessionProvider? _sessionProvider;

  const _NearbyFuelStationRepository(
    this._client,
    this._functionCaller,
    this._sessionProvider,
  );

  @override
  Future<NearbyFuelStationResult> fetchForValidatedSite(
    EastMalaysiaSiteValidationResult validationResult,
  ) async {
    final candidate = validationResult.candidate;
    if (!candidate.isValidatedInside || validationResult.boundaryDatasetId == null) {
      throw ArgumentError(
        'Nearby fuel stations require an authoritative inside site result.',
      );
    }
    if (!(_sessionProvider?.call() ?? _client.auth.currentSession != null)) {
      throw StateError('An authenticated session is required.');
    }

    final body = <String, dynamic>{
      'latitude': candidate.point.latitude,
      'longitude': candidate.point.longitude,
      'analysis_radius_km': candidate.analysisRadiusKm.toInt(),
    };
    final response = await (_functionCaller?.call(
          NearbyFuelStationRepository.functionName,
          body,
        ) ??
        _invokeProductionFunction(body));
    if (response is! Map) {
      throw StateError('Nearby fuel-stations returned an invalid response.');
    }

    return NearbyFuelStationResult.fromMap(
      row: Map<String, dynamic>.from(response),
      expectedPoint: candidate.point,
      expectedAnalysisRadiusKm: candidate.analysisRadiusKm,
    );
  }

  Future<dynamic> _invokeProductionFunction(Map<String, dynamic> body) async {
    final response = await _client.functions.invoke(
      NearbyFuelStationRepository.functionName,
      body: body,
    );
    return response.data;
  }
}
