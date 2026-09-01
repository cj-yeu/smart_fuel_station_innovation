import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/station_assessment_ai_explanation.dart';

typedef StationAssessmentAiExplanationFunctionCaller =
    Future<dynamic> Function(String functionName, Map<String, dynamic> body);
typedef StationAssessmentAiExplanationSessionProvider = bool Function();

class StationAssessmentAiExplanationUnavailableException implements Exception {
  const StationAssessmentAiExplanationUnavailableException();

  @override
  String toString() => 'AI explanation is currently unavailable.';
}

/// Calls the single reviewed Module 2 Edge Function. The app sends only an
/// assessment UUID; all factors and the OpenAI credential remain server-side.
abstract class StationAssessmentAiExplanationRepository {
  static const functionName = 'station-assessment-ai-explanation';

  factory StationAssessmentAiExplanationRepository(
    SupabaseClient client, {
    StationAssessmentAiExplanationFunctionCaller? functionCaller,
    StationAssessmentAiExplanationSessionProvider? sessionProvider,
  }) => _StationAssessmentAiExplanationRepository(
    client,
    functionCaller,
    sessionProvider,
  );

  Future<StationAssessmentAiExplanation> generateExplanation(
    String assessmentId,
  );
}

class _StationAssessmentAiExplanationRepository
    implements StationAssessmentAiExplanationRepository {
  final SupabaseClient _client;
  final StationAssessmentAiExplanationFunctionCaller? _functionCaller;
  final StationAssessmentAiExplanationSessionProvider? _sessionProvider;

  const _StationAssessmentAiExplanationRepository(
    this._client,
    this._functionCaller,
    this._sessionProvider,
  );

  @override
  Future<StationAssessmentAiExplanation> generateExplanation(
    String assessmentId,
  ) async {
    _requireAuthenticated(assessmentId);
    try {
      final response =
          await (_functionCaller?.call(
                StationAssessmentAiExplanationRepository.functionName,
                {'assessment_id': assessmentId},
              ) ??
              _client.functions
                  .invoke(
                    StationAssessmentAiExplanationRepository.functionName,
                    body: {'assessment_id': assessmentId},
                  )
                  .then((response) => response.data));
      return StationAssessmentAiExplanation.fromFunctionResponse(response);
    } catch (_) {
      throw const StationAssessmentAiExplanationUnavailableException();
    }
  }

  void _requireAuthenticated(String assessmentId) {
    if (!RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      caseSensitive: false,
    ).hasMatch(assessmentId)) {
      throw ArgumentError.value(
        assessmentId,
        'assessmentId',
        'Must be a UUID.',
      );
    }
    if (!(_sessionProvider?.call() ?? _client.auth.currentSession != null)) {
      throw const StationAssessmentAiExplanationUnavailableException();
    }
  }
}
