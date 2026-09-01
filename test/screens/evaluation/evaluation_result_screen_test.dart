import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_fuel_station_innovation/models/business_evaluation.dart';
import 'package:smart_fuel_station_innovation/models/business_evaluation_ai_insight.dart';
import 'package:smart_fuel_station_innovation/screens/evaluation/evaluation_result_screen.dart';
import 'package:smart_fuel_station_innovation/services/business_evaluation_ai_insight_repository.dart';
import 'package:smart_fuel_station_innovation/services/business_evaluation_service.dart';

void main() {
  testWidgets('initial card does not generate an insight', (tester) async {
    final repository = _FakeInsightRepository(load: (_) async => null);
    await _pumpResult(tester, repository: repository);

    expect(repository.generateCalls, 0);
    expect(find.text('Generate AI Insight'), findsOneWidget);
    await _scrollUntilVisible(tester, find.text('Rule-based Recommendation'));
    expect(find.text('Rule-based Recommendation'), findsOneWidget);
    await _scrollUntilVisible(tester, find.text('Calculation Summary'));
    expect(find.text('Calculation Summary'), findsOneWidget);
  });

  testWidgets(
    'Generate invokes once, renders structured content, and orders actions',
    (tester) async {
      final repository = _FakeInsightRepository(
        load: (_) async => null,
        generate: (_) async => _insight(),
      );
      await _pumpResult(tester, repository: repository);

      await tester.tap(
        find.byKey(const ValueKey('generate-ai-insight-button')),
      );
      await tester.pumpAndSettle();

      expect(repository.generateCalls, 1);
      expect(find.text('Why This Result'), findsOneWidget);
      expect(find.text('Key Strengths'), findsOneWidget);
      expect(find.text('Key Risks'), findsOneWidget);
      expect(find.text('Recommended Actions'), findsOneWidget);
      expect(find.text('Scenario to Test'), findsOneWidget);
      expect(find.text('Data Limitations'), findsOneWidget);
      expect(
        find.text(
          'AI-generated advisory. Financial calculations remain deterministic '
          'and depend on the assumptions entered.',
        ),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(find.text('Validate demand')).dy,
        lessThan(tester.getTopLeft(find.text('Review margin')).dy),
      );
      expect(
        tester.getTopLeft(find.text('Review margin')).dy,
        lessThan(tester.getTopLeft(find.text('Track utilities')).dy),
      );
    },
  );

  testWidgets('loading disables duplicate Generate taps', (tester) async {
    final completer = Completer<BusinessEvaluationAiInsight>();
    final repository = _FakeInsightRepository(
      load: (_) async => null,
      generate: (_) => completer.future,
    );
    await _pumpResult(tester, repository: repository);

    await tester.tap(find.byKey(const ValueKey('generate-ai-insight-button')));
    await tester.pump();

    final button = tester.widget<ElevatedButton>(
      find.byKey(const ValueKey('generate-ai-insight-button')),
    );
    expect(button.onPressed, isNull);
    expect(repository.generateCalls, 1);

    completer.complete(_insight());
    await tester.pumpAndSettle();
  });

  testWidgets('renders a cached insight without generation', (tester) async {
    final repository = _FakeInsightRepository(
      load: (_) async => _cachedInsight(),
    );
    await _pumpResult(tester, repository: repository);

    expect(repository.generateCalls, 0);
    expect(find.text('Cached insight'), findsOneWidget);
    expect(find.text('Demand supports review.'), findsOneWidget);
  });

  testWidgets('marks stale content and explicitly regenerates it', (
    tester,
  ) async {
    final repository = _FakeInsightRepository(
      load: (_) async =>
          _cachedInsight(sourceUpdatedAt: '2026-08-30T10:00:00.000Z'),
      generate: (_) async => _insight(),
    );
    await _pumpResult(tester, repository: repository);

    expect(
      find.text(
        'This AI insight is outdated because the evaluation was edited.',
      ),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('regenerate-ai-insight-button')),
    );
    await tester.pumpAndSettle();

    expect(repository.generateCalls, 1);
    expect(find.text('Generated insight'), findsOneWidget);
  });

  testWidgets('shows the neutral unavailable fallback for an advisor failure', (
    tester,
  ) async {
    final repository = _FakeInsightRepository(
      load: (_) async => null,
      generate: (_) async =>
          throw const BusinessEvaluationAiInsightUnavailableException(),
    );
    await _pumpResult(tester, repository: repository);

    await tester.tap(find.byKey(const ValueKey('generate-ai-insight-button')));
    await tester.pumpAndSettle();

    expect(find.text('AI insight is currently unavailable.'), findsOneWidget);
    expect(
      find.text('The calculated evaluation above remains valid.'),
      findsOneWidget,
    );
  });

  testWidgets('does not set state after disposal during an advisor request', (
    tester,
  ) async {
    final completer = Completer<BusinessEvaluationAiInsight>();
    final repository = _FakeInsightRepository(
      load: (_) async => null,
      generate: (_) => completer.future,
    );
    await _pumpResult(tester, repository: repository);

    await tester.tap(find.byKey(const ValueKey('generate-ai-insight-button')));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    completer.complete(_insight());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('fits the advisor card on a small screen without overflow', (
    tester,
  ) async {
    final repository = _FakeInsightRepository(
      load: (_) async => _cachedInsight(),
    );
    await _pumpResult(
      tester,
      repository: repository,
      physicalSize: const Size(360, 540),
    );
    await _scrollUntilVisible(
      tester,
      find.byKey(const ValueKey('ai-business-advisor-card')),
    );

    expect(
      find.byKey(const ValueKey('ai-business-advisor-card')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

Future<void> _scrollUntilVisible(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    220,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpResult(
  WidgetTester tester, {
  required _FakeInsightRepository repository,
  Size physicalSize = const Size(700, 2200),
}) async {
  tester.view.physicalSize = physicalSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: EvaluationResultScreen.fromEvaluation(
        _evaluation(),
        aiInsightRepository: repository,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

BusinessEvaluation _evaluation() {
  final result = BusinessEvaluationService.calculate(
    fuelPrice: 3,
    fuelPurchaseCost: 1,
    dailyCustomers: 100,
    averageLitres: 20,
    monthlyRental: 1000,
    monthlyStaffSalary: 1000,
    monthlyUtilities: 400,
    monthlyMaintenance: 200,
    monthlyOtherCost: 100,
    initialInvestment: 100000,
  );
  return BusinessEvaluation.fromCalculatedValues(
    id: '123e4567-e89b-12d3-a456-426614174000',
    userId: '123e4567-e89b-12d3-a456-426614174001',
    stationName: 'Synthetic Station',
    fuelPrice: 3,
    fuelPurchaseCost: 1,
    dailyCustomers: 100,
    averageLitres: 20,
    monthlyRental: 1000,
    monthlyStaffSalary: 1000,
    monthlyUtilities: 400,
    monthlyMaintenance: 200,
    monthlyOtherCost: 100,
    initialInvestment: 100000,
    result: result,
    createdAt: DateTime.parse('2026-08-31T10:00:00.000Z'),
    updatedAt: DateTime.parse('2026-08-31T10:00:00.000Z'),
  );
}

BusinessEvaluationAiInsight _insight() =>
    BusinessEvaluationAiInsight.fromFunctionResponse(_response());

BusinessEvaluationAiInsight _cachedInsight({String? sourceUpdatedAt}) {
  final response = _response();
  response['cache_status'] = 'cached';
  response['source_evaluation_updated_at'] =
      sourceUpdatedAt ?? '2026-08-31T10:00:00.000Z';
  return BusinessEvaluationAiInsight.fromFunctionResponse(response);
}

Map<String, dynamic> _response() => {
  'cache_status': 'generated',
  'insight': {
    'executive_summary': 'Demand supports review.',
    'drivers': [
      {'type': 'risk', 'factor': 'Cost risk', 'evidence': 'Costs can change.'},
      {
        'type': 'strength',
        'factor': 'Demand',
        'evidence': 'Volume is positive.',
      },
    ],
    'actions': [
      {
        'priority': 'low',
        'action': 'Track utilities',
        'reason': 'Utilities affect costs.',
      },
      {
        'priority': 'high',
        'action': 'Validate demand',
        'reason': 'Demand matters most.',
      },
      {
        'priority': 'medium',
        'action': 'Review margin',
        'reason': 'Margin should be monitored.',
      },
    ],
    'scenario_to_test': {
      'variable': 'daily_customers',
      'direction': 'increase',
      'reason': 'Test a conservative range.',
    },
    'data_limitations': ['Inputs are user-provided estimates.'],
    'disclaimer': 'Advisory only.',
  },
  'model': 'gpt-5.6-sol',
  'prompt_version': 'module3.v1',
  'generated_at': '2026-08-31T10:00:00.000Z',
  'source_evaluation_updated_at': '2026-08-31T10:00:00.000Z',
};

class _FakeInsightRepository implements BusinessEvaluationAiInsightRepository {
  final Future<BusinessEvaluationAiInsight?> Function(String) _load;
  final Future<BusinessEvaluationAiInsight> Function(String) _generate;
  int generateCalls = 0;

  _FakeInsightRepository({
    Future<BusinessEvaluationAiInsight?> Function(String)? load,
    Future<BusinessEvaluationAiInsight> Function(String)? generate,
  }) : _load = load ?? ((_) async => null),
       _generate = generate ?? ((_) async => _insight());

  @override
  Future<BusinessEvaluationAiInsight?> loadPersistedInsight(
    String evaluationId,
  ) => _load(evaluationId);

  @override
  Future<BusinessEvaluationAiInsight> generateInsight(String evaluationId) {
    generateCalls += 1;
    return _generate(evaluationId);
  }
}
