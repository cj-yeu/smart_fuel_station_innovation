// ignore_for_file: prefer_initializing_formals

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/station_assessment.dart';
import '../models/station_assessment_create_input.dart';
import '../models/station_assessment_validated_create_input.dart';

typedef ValidatedAssessmentRpcCaller =
    Future<dynamic> Function(String functionName, Map<String, dynamic> params);
typedef AssessmentRowsByIdLoader =
    Future<List<Map<String, dynamic>>> Function(String assessmentId);
typedef AuthenticatedUserIdProvider = String? Function();

class AssessmentDeleteRejectedException implements Exception {
  const AssessmentDeleteRejectedException();

  @override
  String toString() => 'Assessment deletion was rejected.';
}

class AssessmentUpdateRejectedException implements Exception {
  const AssessmentUpdateRejectedException();

  @override
  String toString() => 'Assessment update was rejected.';
}

class StationAssessmentRepository {
  final SupabaseClient _client;
  final ValidatedAssessmentRpcCaller? _validatedAssessmentRpcCaller;
  final AssessmentRowsByIdLoader? _assessmentRowsByIdLoader;
  final AuthenticatedUserIdProvider? _authenticatedUserIdProvider;

  const StationAssessmentRepository(
    this._client, {
    // Named public seams keep repository tests network-free without mocks.
    ValidatedAssessmentRpcCaller? validatedAssessmentRpcCaller,
    AssessmentRowsByIdLoader? assessmentRowsByIdLoader,
    AuthenticatedUserIdProvider? authenticatedUserIdProvider,
  }) : _validatedAssessmentRpcCaller = validatedAssessmentRpcCaller,
       _assessmentRowsByIdLoader = assessmentRowsByIdLoader,
       _authenticatedUserIdProvider = authenticatedUserIdProvider;

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

  /// Creates an assessment for the authenticated user and returns its row.
  ///
  /// The session-derived `user_id` is temporarily sent for compatibility with
  /// the historical schema. The forward migration independently verifies it
  /// against `auth.uid()` and derives authoritative `company_id` from
  /// `profiles.company_id`; neither ownership value comes from the caller.
  Future<StationAssessment> createAssessment(
    StationAssessmentCreateInput input,
  ) async {
    final session = _client.auth.currentSession;
    if (session == null) {
      throw StateError('An authenticated session is required.');
    }

    final data = await _client
        .from('station_assessments')
        .insert({...input.toInsertMap(), 'user_id': session.user.id})
        .select()
        .single();

    return StationAssessment.fromMap(data);
  }

  /// Creates an assessment whose geography is revalidated and persisted by
  /// PostgreSQL in the same transaction.
  ///
  /// Only the 14 content values, candidate coordinates/radius, expected
  /// boundary dataset UUID, and a logical request UUID are sent. The request
  /// UUID makes a retry idempotent; it is not an ownership or authorization
  /// input. Ownership, territory, status, provenance, and validation time are
  /// authoritative RPC outputs and never client input.
  Future<StationAssessment> createValidatedAssessment(
    StationAssessmentValidatedCreateInput input,
  ) async {
    final expectedUserId =
        _authenticatedUserIdProvider?.call() ??
        _client.auth.currentSession?.user.id;
    if (expectedUserId == null || expectedUserId.trim().isEmpty) {
      throw StateError('An authenticated session is required.');
    }

    final response =
        await (_validatedAssessmentRpcCaller?.call(
              'create_validated_station_assessment',
              input.toRpcParams(),
            ) ??
            _client.rpc(
              'create_validated_station_assessment',
              params: input.toRpcParams(),
            ));

    if (response is! String || !_uuidPattern.hasMatch(response)) {
      throw StateError(
        'Validated assessment creation must return exactly one UUID.',
      );
    }

    final rows =
        await (_assessmentRowsByIdLoader?.call(response) ??
            _loadAssessmentRowsById(response));
    if (rows.length != 1) {
      throw StateError(
        'Validated assessment lookup must return exactly one row.',
      );
    }

    final assessment = StationAssessment.fromMap(rows.single);
    if (assessment.id != response || assessment.userId != expectedUserId) {
      throw StateError(
        'Validated assessment response did not match the authenticated creator.',
      );
    }
    return assessment;
  }

  Future<List<Map<String, dynamic>>> _loadAssessmentRowsById(
    String assessmentId,
  ) async {
    final rows = await _client
        .from('station_assessments')
        .select()
        .eq('id', assessmentId)
        .limit(2);
    return rows
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  /// Updates one RLS-authorized assessment by primary key and returns its row.
  ///
  /// [StationAssessmentCreateInput] is temporarily reused because it exactly
  /// represents the 14 writable fields in the legacy manual form. It contains
  /// no identity or ownership fields, so only its content map is sent.
  ///
  /// PostgreSQL RLS decides creator, future same-company admin, and
  /// cross-company authorization without client ownership filters. PostgREST
  /// may return zero rows for a missing or unauthorized record without proving
  /// which case occurred, so verifying the affected-row count is mandatory.
  Future<StationAssessment> updateAssessment(
    String assessmentId,
    StationAssessmentCreateInput input,
  ) async {
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

    final updatedRows = await _client
        .from('station_assessments')
        .update(input.toInsertMap())
        .eq('id', normalizedId)
        .select();

    if (updatedRows.isEmpty) {
      throw const AssessmentUpdateRejectedException();
    }
    if (updatedRows.length > 1) {
      throw StateError('Assessment update affected more than one row.');
    }

    return StationAssessment.fromMap(updatedRows.single);
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
