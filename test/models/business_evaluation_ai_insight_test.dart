import 'package:flutter_test/flutter_test.dart';
import 'package:smart_fuell_station_innovation/models/business_evaluation_ai_insight.dart';

void main() {
  test(
    'strictly parses a generated advisor response and detects stale input',
    () {
      final insight = BusinessEvaluationAiInsight.fromFunctionResponse(
        functionResponse(),
      );

      expect(
        insight.cacheStatus,
        BusinessEvaluationAiInsightCacheStatus.generated,
      );
      expect(
        insight.drivers.first.type,
        BusinessEvaluationAiDriverType.strength,
      );
      expect(
        insight.actions.first.priority,
        BusinessEvaluationAiActionPriority.low,
      );
      expect(
        insight.isStaleFor(DateTime.parse('2026-08-31T12:00:00.000Z')),
        isTrue,
      );
    },
  );

  test(
    'rejects malformed, oversized, and unexpected advisor response values',
    () {
      final unexpected = functionResponse()
        ..['provider_detail'] = 'not allowed';
      expect(
        () => BusinessEvaluationAiInsight.fromFunctionResponse(unexpected),
        throwsFormatException,
      );

      final oversized = functionResponse();
      (oversized['insight'] as Map<String, dynamic>)['executive_summary'] =
          'x' * 1001;
      expect(
        () => BusinessEvaluationAiInsight.fromFunctionResponse(oversized),
        throwsFormatException,
      );

      final invalidAction = functionResponse();
      ((invalidAction['insight'] as Map<String, dynamic>)['actions'] as List)
              .first['priority'] =
          'urgent';
      expect(
        () => BusinessEvaluationAiInsight.fromFunctionResponse(invalidAction),
        throwsFormatException,
      );
    },
  );

  test('parses a cached RLS row with its stored metadata', () {
    final cached = BusinessEvaluationAiInsight.fromStoredRow({
      'evaluation_id': '123e4567-e89b-12d3-a456-426614174000',
      'insight': functionResponse()['insight'],
      'model': 'gpt-5.6-sol',
      'prompt_version': 'module3.v1',
      'input_hash': 'a' * 64,
      'generated_at': '2026-08-31T10:00:00.000Z',
      'source_evaluation_updated_at': '2026-08-31T10:00:00.000Z',
    });

    expect(cached.cacheStatus, BusinessEvaluationAiInsightCacheStatus.cached);
    expect(cached.model, 'gpt-5.6-sol');
  });
}

Map<String, dynamic> functionResponse() => {
  'cache_status': 'generated',
  'insight': {
    'executive_summary': 'Demand and cost assumptions support review.',
    'drivers': [
      {
        'type': 'strength',
        'factor': 'Demand',
        'evidence': 'Projected volume is positive.',
      },
    ],
    'actions': [
      {
        'priority': 'low',
        'action': 'Track utilities',
        'reason': 'Utilities influence fixed costs.',
      },
      {
        'priority': 'high',
        'action': 'Validate demand',
        'reason': 'Demand is the main sensitivity.',
      },
      {
        'priority': 'medium',
        'action': 'Review margin',
        'reason': 'Margin affects profitability.',
      },
    ],
    'scenario_to_test': {
      'variable': 'daily_customers',
      'direction': 'increase',
      'reason': 'Test a conservative demand range.',
    },
    'data_limitations': ['Inputs are user-provided estimates.'],
    'disclaimer': 'Advisory only.',
  },
  'model': 'gpt-5.6-sol',
  'prompt_version': 'module3.v1',
  'generated_at': '2026-08-31T10:00:00.000Z',
  'source_evaluation_updated_at': '2026-08-31T10:00:00.000Z',
};
