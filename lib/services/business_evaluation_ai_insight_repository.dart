import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/business_evaluation_ai_insight.dart';

typedef BusinessEvaluationAiInsightFunctionCaller =
    Future<dynamic> Function(String functionName, Map<String, dynamic> body);
typedef BusinessEvaluationAiInsightStoredLoader =
    Future<dynamic> Function(String evaluationId);
typedef BusinessEvaluationAiInsightSessionProvider = bool Function();

class BusinessEvaluationAiInsightUnavailableException implements Exception {
  const BusinessEvaluationAiInsightUnavailableException();

  @override
  String toString() => 'AI insight is currently unavailable.';
}

/// Reads the caller's persisted insight through RLS or explicitly requests a
/// new insight from the single reviewed Edge Function. The client sends only
/// the evaluation identifier; ownership, model selection, financial inputs,
/// and provider credentials remain server-side.
abstract class BusinessEvaluationAiInsightRepository {
  static const functionName = 'business-evaluation-ai-insight';

  factory BusinessEvaluationAiInsightRepository(
    SupabaseClient client, {
    BusinessEvaluationAiInsightFunctionCaller? functionCaller,
    BusinessEvaluationAiInsightStoredLoader? storedLoader,
    BusinessEvaluationAiInsightSessionProvider? sessionProvider,
  }) => _BusinessEvaluationAiInsightRepository(
    client,
    functionCaller,
    storedLoader,
    sessionProvider,
  );

  /// Loads a previously stored, RLS-visible insight without generating one.
  Future<BusinessEvaluationAiInsight?> loadPersistedInsight(
    String evaluationId,
  );

  /// Generates or returns the server's valid cached insight for [evaluationId].
  Future<BusinessEvaluationAiInsight> generateInsight(String evaluationId);
}

class _BusinessEvaluationAiInsightRepository
    implements BusinessEvaluationAiInsightRepository {
  final SupabaseClient _client;
  final BusinessEvaluationAiInsightFunctionCaller? _functionCaller;
  final BusinessEvaluationAiInsightStoredLoader? _storedLoader;
  final BusinessEvaluationAiInsightSessionProvider? _sessionProvider;

  const _BusinessEvaluationAiInsightRepository(
    this._client,
    this._functionCaller,
    this._storedLoader,
    this._sessionProvider,
  );

  @override
  Future<BusinessEvaluationAiInsight?> loadPersistedInsight(
    String evaluationId,
  ) async {
    _requireAuthenticated(evaluationId);
    try {
      final response =
          await (_storedLoader?.call(evaluationId) ??
              _loadPersistedProduction(evaluationId));
      if (response is! List) {
        throw const FormatException('Stored AI insight response is invalid.');
      }
      if (response.isEmpty) return null;
      if (response.length != 1) {
        throw const FormatException('Stored AI insight response is ambiguous.');
      }
      return BusinessEvaluationAiInsight.fromStoredRow(response.single);
    } catch (_) {
      throw const BusinessEvaluationAiInsightUnavailableException();
    }
  }

  @override
  Future<BusinessEvaluationAiInsight> generateInsight(
    String evaluationId,
  ) async {
    _requireAuthenticated(evaluationId);
    try {
      final response =
          await (_functionCaller?.call(
                BusinessEvaluationAiInsightRepository.functionName,
                {'evaluation_id': evaluationId},
              ) ??
              _invokeProductionFunction(evaluationId));
      return BusinessEvaluationAiInsight.fromFunctionResponse(response);
    } catch (_) {
      throw const BusinessEvaluationAiInsightUnavailableException();
    }
  }

  void _requireAuthenticated(String evaluationId) {
    if (!RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      caseSensitive: false,
    ).hasMatch(evaluationId)) {
      throw ArgumentError.value(
        evaluationId,
        'evaluationId',
        'Must be a UUID.',
      );
    }
    if (!(_sessionProvider?.call() ?? _client.auth.currentSession != null)) {
      throw const BusinessEvaluationAiInsightUnavailableException();
    }
  }

  Future<dynamic> _loadPersistedProduction(String evaluationId) {
    return _client
        .from('business_evaluation_ai_insights')
        .select(
          'evaluation_id,insight,model,prompt_version,input_hash,'
          'source_evaluation_updated_at,generated_at',
        )
        .eq('evaluation_id', evaluationId)
        .limit(2);
  }

  Future<dynamic> _invokeProductionFunction(String evaluationId) async {
    final response = await _client.functions.invoke(
      BusinessEvaluationAiInsightRepository.functionName,
      body: {'evaluation_id': evaluationId},
    );
    return response.data;
  }
}
