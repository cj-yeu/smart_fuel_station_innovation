import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/east_malaysia_site_validation_result.dart';
import '../models/site_factor_intelligence_result.dart';

typedef SiteFactorIntelligenceFunctionCaller =
    Future<dynamic> Function(String functionName, Map<String, dynamic> body);
typedef SiteFactorIntelligenceSessionProvider = bool Function();

abstract class SiteFactorIntelligenceRepository {
  static const functionName = 'site-factor-intelligence';

  factory SiteFactorIntelligenceRepository(
    SupabaseClient client, {
    SiteFactorIntelligenceFunctionCaller? functionCaller,
    SiteFactorIntelligenceSessionProvider? sessionProvider,
  }) => _SiteFactorIntelligenceRepository(
    client,
    functionCaller,
    sessionProvider,
  );

  Future<SiteFactorIntelligenceResult> fetchForValidatedSite(
    EastMalaysiaSiteValidationResult validationResult,
  );
}

class _SiteFactorIntelligenceRepository
    implements SiteFactorIntelligenceRepository {
  final SupabaseClient _client;
  final SiteFactorIntelligenceFunctionCaller? _functionCaller;
  final SiteFactorIntelligenceSessionProvider? _sessionProvider;

  const _SiteFactorIntelligenceRepository(
    this._client,
    this._functionCaller,
    this._sessionProvider,
  );

  @override
  Future<SiteFactorIntelligenceResult> fetchForValidatedSite(
    EastMalaysiaSiteValidationResult validationResult,
  ) async {
    final candidate = validationResult.candidate;
    if (!candidate.isValidatedInside ||
        validationResult.boundaryDatasetId == null) {
      throw ArgumentError(
        'Site-factor intelligence requires an authoritative inside site result.',
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
    final response =
        await (_functionCaller?.call(
              SiteFactorIntelligenceRepository.functionName,
              body,
            ) ??
            _invokeProductionFunction(body));
    if (response is! Map) {
      throw StateError(
        'Site-factor intelligence returned an invalid response.',
      );
    }
    return SiteFactorIntelligenceResult.fromMap(
      row: Map<String, dynamic>.from(response),
      expectedPoint: candidate.point,
      expectedAnalysisRadiusKm: candidate.analysisRadiusKm,
    );
  }

  Future<dynamic> _invokeProductionFunction(Map<String, dynamic> body) async {
    final response = await _client.functions.invoke(
      SiteFactorIntelligenceRepository.functionName,
      body: body,
    );
    return response.data;
  }
}
