import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/station_assessment.dart';

class AssessmentDeleteRejectedException implements Exception {
  const AssessmentDeleteRejectedException();

  @override
  String toString() => 'Assessment deletion was rejected.';
}

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

  /// Deletes one RLS-authorized assessment by primary key.
  ///
  /// PostgreSQL RLS, rather than client-supplied ownership filters, decides
  /// whether the row may be deleted. The returned ID is checked because an
  /// RLS-rejected delete can succeed at the protocol level while affecting no
  /// rows, which must not be reported as a successful deletion.
  Future<void> deleteAssessment(String assessmentId) async {
    final normalizedId = assessmentId.trim();
    if (normalizedId.isEmpty) {
      throw ArgumentError.value(
        assessmentId,
        'assessmentId',
        'Assessment ID must not be blank.',
      );
    }

    if (_client.auth.currentSession == null) {
      throw StateError('An authenticated session is required.');
    }

    final deletedRows = await _client
        .from('station_assessments')
        .delete()
        .eq('id', normalizedId)
        .select('id');

    if (deletedRows.length == 1) return;
    if (deletedRows.isEmpty) {
      throw const AssessmentDeleteRejectedException();
    }

    throw StateError('Assessment deletion affected more than one row.');
  }
}
