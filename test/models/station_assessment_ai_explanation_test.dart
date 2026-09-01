import 'package:flutter_test/flutter_test.dart';
import 'package:smart_fuell_station_innovation/models/station_assessment_ai_explanation.dart';

void main() {
  test('strictly parses the small station-assessment explanation response', () {
    final explanation = StationAssessmentAiExplanation.fromFunctionResponse({
      'explanation': 'The deterministic score reflects the supplied inputs.',
    });

    expect(
      explanation.explanation,
      'The deterministic score reflects the supplied inputs.',
    );
  });

  test('rejects missing, oversized, and unexpected response fields', () {
    expect(
      () => StationAssessmentAiExplanation.fromFunctionResponse({}),
      throwsFormatException,
    );
    expect(
      () => StationAssessmentAiExplanation.fromFunctionResponse({
        'explanation': 'x' * 1401,
      }),
      throwsFormatException,
    );
    expect(
      () => StationAssessmentAiExplanation.fromFunctionResponse({
        'explanation': 'Valid text.',
        'provider_detail': 'must not be accepted',
      }),
      throwsFormatException,
    );
  });
}
