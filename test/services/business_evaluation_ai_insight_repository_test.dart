import 'package:flutter_test/flutter_test.dart';
import 'package:smart_fuel_station_innovation/services/business_evaluation_ai_insight_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  const evaluationId = '123e4567-e89b-12d3-a456-426614174000';

  test(
    'loads a persisted insight without invoking the Edge Function',
    () async {
      var functionCalls = 0;
      final repository = BusinessEvaluationAiInsightRepository(
        SupabaseClient('https://example.invalid', 'test-anon-key'),
        sessionProvider: () => true,
        storedLoader: (_) async => [storedRow()],
        functionCaller: (_, _) async {
          functionCalls += 1;
          return functionResponse();
        },
      );

      final insight = await repository.loadPersistedInsight(evaluationId);

      expect(insight, isNotNull);
      expect(functionCalls, 0);
    },
  );

  test('invokes only the reviewed function with only evaluation_id', () async {
    String? functionName;
    Map<String, dynamic>? functionBody;
    final repository = BusinessEvaluationAiInsightRepository(
      SupabaseClient('https://example.invalid', 'test-anon-key'),
      sessionProvider: () => true,
      functionCaller: (name, body) async {
        functionName = name;
        functionBody = body;
        return functionResponse();
      },
    );

    await repository.generateInsight(evaluationId);

    expect(functionName, 'business-evaluation-ai-insight');
    expect(functionBody, {'evaluation_id': evaluationId});
  });

  test(
    'maps malformed responses and unavailable sessions to one neutral error',
    () async {
      final malformed = BusinessEvaluationAiInsightRepository(
        SupabaseClient('https://example.invalid', 'test-anon-key'),
        sessionProvider: () => true,
        functionCaller: (_, _) async => {'cache_status': 'generated'},
      );
      final anonymous = BusinessEvaluationAiInsightRepository(
        SupabaseClient('https://example.invalid', 'test-anon-key'),
        sessionProvider: () => false,
        functionCaller: (_, _) async => functionResponse(),
      );

      await expectLater(
        malformed.generateInsight(evaluationId),
        throwsA(isA<BusinessEvaluationAiInsightUnavailableException>()),
      );
      await expectLater(
        anonymous.generateInsight(evaluationId),
        throwsA(isA<BusinessEvaluationAiInsightUnavailableException>()),
      );
    },
  );
}

Map<String, dynamic> storedRow() => {
  'evaluation_id': '123e4567-e89b-12d3-a456-426614174000',
  'insight': functionResponse()['insight'],
  'model': 'gpt-5.6-sol',
  'prompt_version': 'module3.v1',
  'input_hash': 'a' * 64,
  'generated_at': '2026-08-31T10:00:00.000Z',
  'source_evaluation_updated_at': '2026-08-31T10:00:00.000Z',
};

Map<String, dynamic> functionResponse() => {
  'cache_status': 'generated',
  'insight': {
    'executive_summary': 'Demand supports review.',
    'drivers': [
      {'type': 'strength', 'factor': 'Demand', 'evidence': 'Positive volume.'},
    ],
    'actions': [
      {'priority': 'high', 'action': 'Test demand', 'reason': 'It matters.'},
      {
        'priority': 'medium',
        'action': 'Review margin',
        'reason': 'It matters.',
      },
      {'priority': 'low', 'action': 'Track costs', 'reason': 'It matters.'},
    ],
    'scenario_to_test': {
      'variable': 'daily_customers',
      'direction': 'increase',
      'reason': 'Test a range.',
    },
    'data_limitations': <String>[],
    'disclaimer': 'Advisory only.',
  },
  'model': 'gpt-5.6-sol',
  'prompt_version': 'module3.v1',
  'generated_at': '2026-08-31T10:00:00.000Z',
  'source_evaluation_updated_at': '2026-08-31T10:00:00.000Z',
};
