class StationAssessmentAiExplanation {
  final String explanation;

  const StationAssessmentAiExplanation({required this.explanation});

  factory StationAssessmentAiExplanation.fromFunctionResponse(Object? value) {
    if (value is! Map ||
        value.length != 1 ||
        !value.containsKey('explanation')) {
      throw const FormatException('AI explanation response is invalid.');
    }

    final explanation = value['explanation'];
    if (explanation is! String ||
        explanation.trim().isEmpty ||
        explanation.length > 1400) {
      throw const FormatException('AI explanation response is invalid.');
    }

    return StationAssessmentAiExplanation(explanation: explanation);
  }
}
