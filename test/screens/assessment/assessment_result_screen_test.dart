import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_fuel_station_innovation/models/station_assessment_ai_explanation.dart';
import 'package:smart_fuel_station_innovation/screens/assessment/assessment_result_screen.dart';
import 'package:smart_fuel_station_innovation/services/station_assessment_ai_explanation_repository.dart';
import 'package:smart_fuel_station_innovation/services/station_assessment_service.dart';

void main() {
  const assessmentId = '123e4567-e89b-12d3-a456-426614174000';

  testWidgets('only the AI Explanation content is replaced by GPT text', (
    tester,
  ) async {
    var calls = 0;
    await pumpScreen(
      tester,
      assessmentId: assessmentId,
      generator: (_) async {
        calls += 1;
        return const StationAssessmentAiExplanation(
          explanation: 'GPT explains the existing deterministic result.',
        );
      },
    );

    expect(calls, 1);
    expect(find.text('72.5'), findsOneWidget);
    expect(find.text('Good'), findsOneWidget);
    expect(
      find.text('This location is recommended for fuel station development.'),
      findsOneWidget,
    );
    await scrollResultContentIntoView(
      tester,
      find.text('GPT explains the existing deterministic result.'),
    );
    expect(
      find.text('GPT explains the existing deterministic result.'),
      findsOneWidget,
    );
  });

  testWidgets('shows loading while generating and prevents duplicate calls', (
    tester,
  ) async {
    final completer = Completer<StationAssessmentAiExplanation>();
    var calls = 0;
    await pumpScreen(
      tester,
      assessmentId: assessmentId,
      generator: (_) {
        calls += 1;
        return completer.future;
      },
      settle: false,
    );

    await tester.pump();
    await scrollResultContentIntoView(
      tester,
      find.text('Generating AI explanation...'),
      settle: false,
    );
    expect(find.text('Generating AI explanation...'), findsOneWidget);
    expect(calls, 1);

    completer.complete(
      const StationAssessmentAiExplanation(explanation: 'Generated safely.'),
    );
    await tester.pumpAndSettle();
    expect(calls, 1);
  });

  testWidgets('falls back safely and retries without changing the result', (
    tester,
  ) async {
    var calls = 0;
    await pumpScreen(
      tester,
      assessmentId: assessmentId,
      generator: (_) async {
        calls += 1;
        if (calls == 1) {
          throw const StationAssessmentAiExplanationUnavailableException();
        }
        return const StationAssessmentAiExplanation(
          explanation: 'Retried GPT text.',
        );
      },
    );

    await scrollResultContentIntoView(
      tester,
      find.text(
        'AI explanation is currently unavailable. The deterministic assessment result above remains valid.',
      ),
    );
    expect(
      find.text(
        'AI explanation is currently unavailable. The deterministic assessment result above remains valid.',
      ),
      findsOneWidget,
    );
    expect(find.text('Deterministic fallback explanation.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('retry-ai-explanation-button')));
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(find.text('Retried GPT text.'), findsOneWidget);
    expect(
      find.text('This location is recommended for fuel station development.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'keeps the deterministic fallback without a saved assessment ID',
    (tester) async {
      var calls = 0;
      await pumpScreen(
        tester,
        generator: (_) async {
          calls += 1;
          return const StationAssessmentAiExplanation(
            explanation: 'Unexpected',
          );
        },
      );

      expect(calls, 0);
      await scrollResultContentIntoView(
        tester,
        find.text('Deterministic fallback explanation.'),
      );
      expect(find.text('Deterministic fallback explanation.'), findsOneWidget);
    },
  );
}

Future<void> pumpScreen(
  WidgetTester tester, {
  String? assessmentId,
  required StationAssessmentAiExplanationGenerator generator,
  bool settle = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: AssessmentResultScreen(
        locationName: 'Synthetic Site',
        assessmentId: assessmentId,
        aiExplanationGenerator: generator,
        result: const AssessmentResult(
          finalScore: 72.5,
          category: 'Good',
          recommendation:
              'This location is recommended for fuel station development.',
          explanation: 'Deterministic fallback explanation.',
        ),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}

Future<void> scrollResultContentIntoView(
  WidgetTester tester,
  Finder content, {
  bool settle = true,
}) async {
  final scrollable = find.descendant(
    of: find.byType(AssessmentResultScreen),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    ),
  );

  expect(scrollable, findsOneWidget);
  await tester.scrollUntilVisible(content, 200, scrollable: scrollable);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}
