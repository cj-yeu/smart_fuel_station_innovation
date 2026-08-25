class BusinessEvaluationResult {
  final double monthlySalesVolume;
  final double monthlyRevenue;
  final double monthlyFuelCost;
  final double monthlyOperatingCost;
  final double monthlyProfit;
  final double profitMargin;
  final double roi;
  final double? breakEvenMonths;
  final double profitabilityScore;
  final String category;
  final String recommendation;
  final String explanation;

  const BusinessEvaluationResult({
    required this.monthlySalesVolume,
    required this.monthlyRevenue,
    required this.monthlyFuelCost,
    required this.monthlyOperatingCost,
    required this.monthlyProfit,
    required this.profitMargin,
    required this.roi,
    required this.breakEvenMonths,
    required this.profitabilityScore,
    required this.category,
    required this.recommendation,
    required this.explanation,
  });
}

class BusinessEvaluationService {
  static BusinessEvaluationResult calculate({
    required double fuelPrice,
    required double fuelPurchaseCost,
    required int dailyCustomers,
    required double averageLitres,
    required double monthlyRental,
    required double monthlyStaffSalary,
    required double monthlyUtilities,
    required double monthlyMaintenance,
    required double monthlyOtherCost,
    required double initialInvestment,
  }) {
    final numericInputs = [
      fuelPrice,
      fuelPurchaseCost,
      averageLitres,
      monthlyRental,
      monthlyStaffSalary,
      monthlyUtilities,
      monthlyMaintenance,
      monthlyOtherCost,
      initialInvestment,
    ];
    if (numericInputs.any((value) => !value.isFinite)) {
      throw ArgumentError('Evaluation inputs must be finite numbers.');
    }
    if (dailyCustomers < 0 || numericInputs.any((value) => value < 0)) {
      throw ArgumentError('Evaluation inputs cannot be negative.');
    }
    if (fuelPrice <= fuelPurchaseCost) {
      throw ArgumentError('Selling price must be greater than purchase cost.');
    }

    final monthlySalesVolume = dailyCustomers * averageLitres * 30;

    final monthlyRevenue = monthlySalesVolume * fuelPrice;

    final monthlyFuelCost = monthlySalesVolume * fuelPurchaseCost;

    final fixedOperatingCost =
        monthlyRental +
        monthlyStaffSalary +
        monthlyUtilities +
        monthlyMaintenance +
        monthlyOtherCost;

    final monthlyOperatingCost = monthlyFuelCost + fixedOperatingCost;

    final monthlyProfit = monthlyRevenue - monthlyOperatingCost;

    final profitMargin = monthlyRevenue == 0
        ? 0.0
        : (monthlyProfit / monthlyRevenue) * 100;

    final annualProfit = monthlyProfit * 12;

    final roi = initialInvestment == 0
        ? 0.0
        : (annualProfit / initialInvestment) * 100;

    _requireFiniteCalculatedValues([
      monthlySalesVolume,
      monthlyRevenue,
      monthlyFuelCost,
      monthlyOperatingCost,
      monthlyProfit,
      profitMargin,
      annualProfit,
      roi,
    ]);

    final double? breakEvenMonths = monthlyProfit > 0 && initialInvestment > 0
        ? initialInvestment / monthlyProfit
        : null;
    if (breakEvenMonths != null && !breakEvenMonths.isFinite) {
      throw ArgumentError('Evaluation results must be finite numbers.');
    }

    final marginScore = ((profitMargin / 20) * 100).clamp(0, 100).toDouble();

    final roiScore = ((roi / 30) * 100).clamp(0, 100).toDouble();

    final demandScore = ((monthlySalesVolume / 150000) * 100)
        .clamp(0, 100)
        .toDouble();

    final breakEvenScore = _calculateBreakEvenScore(breakEvenMonths);

    final profitabilityScore =
        (marginScore * 0.40 +
                roiScore * 0.25 +
                breakEvenScore * 0.20 +
                demandScore * 0.15)
            .clamp(0, 100)
            .toDouble();

    final roundedScore = _round(profitabilityScore);
    final roundedProfit = _round(monthlyProfit);
    final roundedMargin = _round(profitMargin);
    final roundedRoi = _round(roi);

    String category;
    String recommendation;

    if (roundedScore >= 70 && monthlyProfit > 0) {
      category = 'Profitable';
      recommendation =
          'The proposed fuel station shows strong financial potential.';
    } else if (roundedScore >= 45 && monthlyProfit > 0) {
      category = 'Moderate Risk';
      recommendation =
          'The station may be viable, but costs and customer demand should be reviewed.';
    } else {
      category = 'High Risk';
      recommendation =
          'The current business assumptions indicate high financial risk.';
    }

    final explanation = _buildExplanation(
      monthlyProfit: roundedProfit,
      profitMargin: roundedMargin,
      roi: roundedRoi,
      breakEvenMonths: breakEvenMonths,
    );

    return BusinessEvaluationResult(
      monthlySalesVolume: _round(monthlySalesVolume),
      monthlyRevenue: _round(monthlyRevenue),
      monthlyFuelCost: _round(monthlyFuelCost),
      monthlyOperatingCost: _round(monthlyOperatingCost),
      monthlyProfit: roundedProfit,
      profitMargin: roundedMargin,
      roi: roundedRoi,
      breakEvenMonths: breakEvenMonths == null ? null : _round(breakEvenMonths),
      profitabilityScore: roundedScore,
      category: category,
      recommendation: recommendation,
      explanation: explanation,
    );
  }

  static double _calculateBreakEvenScore(double? breakEvenMonths) {
    if (breakEvenMonths == null) return 0;
    if (breakEvenMonths <= 24) return 100;
    if (breakEvenMonths <= 48) return 70;
    if (breakEvenMonths <= 72) return 40;
    return 20;
  }

  static String _buildExplanation({
    required double monthlyProfit,
    required double profitMargin,
    required double roi,
    required double? breakEvenMonths,
  }) {
    final breakEvenText = breakEvenMonths == null
        ? 'The station is not currently profitable under the current assumptions.'
        : 'The estimated break-even period is '
              '${breakEvenMonths.toStringAsFixed(1)} months.';

    return 'Estimated monthly profit is '
        'RM${monthlyProfit.toStringAsFixed(2)}, '
        'with a profit margin of '
        '${profitMargin.toStringAsFixed(2)}% and '
        'an annual ROI of ${roi.toStringAsFixed(2)}%. '
        '$breakEvenText';
  }

  static double _round(double value) {
    if (!value.isFinite) {
      throw ArgumentError('Evaluation results must be finite numbers.');
    }
    return double.parse(value.toStringAsFixed(2));
  }

  static void _requireFiniteCalculatedValues(Iterable<double> values) {
    if (values.any((value) => !value.isFinite)) {
      throw ArgumentError('Evaluation results must be finite numbers.');
    }
  }
}
