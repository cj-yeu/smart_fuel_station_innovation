import 'package:flutter_test/flutter_test.dart';
import 'package:smart_fuel_station_innovation/services/station_assessment_ai_explanation_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  const assessmentId = '123e4567-e89b-12d3-a456-426614174000';

  test('invokes only the reviewed function with only assessment_id', () async {
    String? functionName;
    Map<String, dynamic>? functionBody;
    final repository = StationAssessmentAiExplanationRepository(
      SupabaseClient('https://example.invalid', 'test-anon-key'),
      sessionProvider: () => true,
      functionCaller: (name, body) async {
        functionName = name;
        functionBody = body;
        return {'explanation': 'Generated explanation.'};
      },
    );

    await repository.generateExplanation(assessmentId);

    expect(functionName, 'station-assessment-ai-explanation');
    expect(functionBody, {'assessment_id': assessmentId});
  });

  test(
    'maps malformed responses and unavailable sessions to a neutral error',
    () async {
      final malformed = StationAssessmentAiExplanationRepository(
        SupabaseClient('https://example.invalid', 'test-anon-key'),
        sessionProvider: () => true,
        functionCaller: (_, _) async => {'unexpected': 'response'},
      );
      final anonymous = StationAssessmentAiExplanationRepository(
        SupabaseClient('https://example.invalid', 'test-anon-key'),
        sessionProvider: () => false,
        functionCaller: (_, _) async => {'explanation': 'Never called.'},
      );

      await expectLater(
        malformed.generateExplanation(assessmentId),
        throwsA(isA<StationAssessmentAiExplanationUnavailableException>()),
      );
      await expectLater(
        anonymous.generateExplanation(assessmentId),
        throwsA(isA<StationAssessmentAiExplanationUnavailableException>()),
      );
    },
  );

  test(
    'rejects malformed assessment IDs before invoking the function',
    () async {
      var calls = 0;
      final repository = StationAssessmentAiExplanationRepository(
        SupabaseClient('https://example.invalid', 'test-anon-key'),
        sessionProvider: () => true,
        functionCaller: (_, _) async {
          calls += 1;
          return {'explanation': 'Never called.'};
        },
      );

      await expectLater(
        repository.generateExplanation('not-a-uuid'),
        throwsArgumentError,
      );
      expect(calls, 0);
    },
  );
}
