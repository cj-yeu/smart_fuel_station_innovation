import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/assessment_site_candidate.dart';
import '../models/east_malaysia_site_validation_result.dart';
import '../models/geo_point.dart';

class EastMalaysiaGeographyRepository {
  final SupabaseClient _client;

  const EastMalaysiaGeographyRepository(this._client);

  /// Validates a candidate through the authoritative PostgreSQL geography RPC.
  ///
  /// The client sends no ownership value and performs no company lookup. The
  /// RPC resolves company membership from `profiles.company_id` and fails
  /// closed when authoritative boundary data cannot confirm the point.
  Future<EastMalaysiaSiteValidationResult> validateSite({
    required GeoPoint point,
    required double analysisRadiusKm,
  }) async {
    if (!analysisRadiusKm.isFinite ||
        !AssessmentSiteCandidate.supportedAnalysisRadiiKm.contains(
          analysisRadiusKm,
        )) {
      throw ArgumentError.value(
        analysisRadiusKm,
        'analysisRadiusKm',
        'Analysis radius must be exactly 3, 5, or 10 kilometres.',
      );
    }

    if (_client.auth.currentSession == null) {
      throw StateError('An authenticated session is required.');
    }

    final response = await _client.rpc(
      'validate_east_malaysia_site',
      params: {
        'p_latitude': point.latitude,
        'p_longitude': point.longitude,
        'p_analysis_radius_km': analysisRadiusKm.toInt(),
      },
    );

    if (response is! List || response.length != 1) {
      throw StateError(
        'Geographic validation must return exactly one result row.',
      );
    }

    final row = response.single;
    if (row is! Map) {
      throw StateError('Geographic validation returned an invalid result row.');
    }

    return EastMalaysiaSiteValidationResult.fromRpcRow(
      row: Map<String, dynamic>.from(row),
      point: point,
      analysisRadiusKm: analysisRadiusKm,
    );
  }
}
