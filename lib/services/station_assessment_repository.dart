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
    ValidatedAssessmentRpcCaller? validatedAssessmentRpcCaller,
    AssessmentRowsByIdLoader? assessmentRowsByIdLoader,
    AuthenticatedUserIdProvider? authenticatedUserIdProvider,
  }) : _validatedAssessmentRpcCaller = validatedAssessmentRpcCaller,
       _assessmentRowsByIdLoader = assessmentRowsByIdLoader,
       _authenticatedUserIdProvider = authenticatedUserIdProvider;

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
