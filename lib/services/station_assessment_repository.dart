import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/station_assessment.dart';

class StationAssessmentRepository {
  final SupabaseClient _client;

  const StationAssessmentRepository(this._client);

  /// Fetches the current company's RLS-visible assessments, newest first.
  ///
  /// There is intentionally no client-side company filter. PostgreSQL RLS
  /// resolves `auth.uid()` through the authoritative `profiles.company_id`, so
  /// the client neither supplies nor trusts a company ownership value.
  Future<List<StationAssessment>> fetchCompanyAssessments() async {
    if (_client.auth.currentSession == null) {
      throw StateError('An authenticated session is required.');
    }

    final data = await _client
        .from('station_assessments')
        .select()
        .order('created_at', ascending: false);

    return data
        .map((item) => StationAssessment.fromMap(item))
        .toList(growable: false);
  }
}
