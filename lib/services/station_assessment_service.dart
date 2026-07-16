class AssessmentResult {
  final double finalScore;
  final String category;
  final String recommendation;
  final String explanation;

  const AssessmentResult({
    required this.finalScore,
    required this.category,
    required this.recommendation,
    required this.explanation,
  });
}

class StationAssessmentService {
  static AssessmentResult calculate({
    required double populationDensity,
    required int trafficLevel,
    required int registeredVehicleCount,
    required int nearbyFuelStations,
    required double competitorDistanceKm,
    required int roadAccessibility,
    required int commercialActivity,
    required int residentialActivity,
    required int landAccessibility,
  }) {
    final populationScore = _percentage(
      populationDensity,
      maximum: 10000,
    );

    final trafficScore = trafficLevel * 20.0;

    final vehicleScore = _percentage(
      registeredVehicleCount.toDouble(),
      maximum: 100000,
    );

    final nearbyStationScore = (100 - (nearbyFuelStations * 20))
        .clamp(0, 100)
        .toDouble();

    final competitorDistanceScore = _percentage(
      competitorDistanceKm,
      maximum: 5,
    );

    final competitionScore =
        (nearbyStationScore + competitorDistanceScore) / 2;

    final roadScore = roadAccessibility * 20.0;
    final commercialScore = commercialActivity * 20.0;
    final residentialScore = residentialActivity * 20.0;
    final landScore = landAccessibility * 20.0;

    final finalScore = (
        populationScore * 0.15 +
            trafficScore * 0.20 +
            vehicleScore * 0.15 +
            competitionScore * 0.15 +
            roadScore * 0.15 +
            commercialScore * 0.10 +
            residentialScore * 0.05 +
            landScore * 0.05
    ).clamp(0, 100).toDouble();

    final roundedScore =
    double.parse(finalScore.toStringAsFixed(1));

    if (roundedScore >= 70) {
      return AssessmentResult(
        finalScore: roundedScore,
        category: 'Good',
        recommendation:
        'This location is recommended for fuel station development.',
        explanation: _buildExplanation(
          score: roundedScore,
          populationScore: populationScore,
          trafficScore: trafficScore,
          competitionScore: competitionScore,
          roadScore: roadScore,
        ),
      );
    }

    if (roundedScore >= 45) {
      return AssessmentResult(
        finalScore: roundedScore,
        category: 'Moderate',
        recommendation:
        'This location has potential but requires further investigation.',
        explanation: _buildExplanation(
          score: roundedScore,
          populationScore: populationScore,
          trafficScore: trafficScore,
          competitionScore: competitionScore,
          roadScore: roadScore,
        ),
      );
    }

    return AssessmentResult(
      finalScore: roundedScore,
      category: 'Poor',
      recommendation:
      'This location is not currently recommended for development.',
      explanation: _buildExplanation(
        score: roundedScore,
        populationScore: populationScore,
        trafficScore: trafficScore,
        competitionScore: competitionScore,
        roadScore: roadScore,
      ),
    );
  }

  static double _percentage(
      double value, {
        required double maximum,
      }) {
    if (value <= 0) return 0;

    return ((value / maximum) * 100)
        .clamp(0, 100)
        .toDouble();
  }

  static String _buildExplanation({
    required double score,
    required double populationScore,
    required double trafficScore,
    required double competitionScore,
    required double roadScore,
  }) {
    final strengths = <String>[];
    final weaknesses = <String>[];

    _classifyFactor(
      name: 'population demand',
      score: populationScore,
      strengths: strengths,
      weaknesses: weaknesses,
    );

    _classifyFactor(
      name: 'traffic level',
      score: trafficScore,
      strengths: strengths,
      weaknesses: weaknesses,
    );

    _classifyFactor(
      name: 'competition conditions',
      score: competitionScore,
      strengths: strengths,
      weaknesses: weaknesses,
    );

    _classifyFactor(
      name: 'road accessibility',
      score: roadScore,
      strengths: strengths,
      weaknesses: weaknesses,
    );

    final strengthText = strengths.isEmpty
        ? 'No major strengths were identified'
        : 'Main strengths: ${strengths.join(', ')}';

    final weaknessText = weaknesses.isEmpty
        ? 'No major weaknesses were identified'
        : 'Factors requiring attention: ${weaknesses.join(', ')}';

    return 'The AI suitability score is '
        '${score.toStringAsFixed(1)} out of 100. '
        '$strengthText. $weaknessText.';
  }

  static void _classifyFactor({
    required String name,
    required double score,
    required List<String> strengths,
    required List<String> weaknesses,
  }) {
    if (score >= 70) {
      strengths.add(name);
    } else if (score < 45) {
      weaknesses.add(name);
    }
  }
}