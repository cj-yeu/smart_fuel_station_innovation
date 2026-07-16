class BusinessEvaluation {
  final String id;
  final String userId;
  final String stationName;
  final double fuelPrice;
  final double fuelPurchaseCost;
  final int dailyCustomers;
  final double averageLitres;
  final double monthlyRental;
  final double monthlyStaffSalary;
  final double monthlyUtilities;
  final double monthlyMaintenance;
  final double monthlyOtherCost;
  final double initialInvestment;
  final double monthlySalesVolume;
  final double monthlyRevenue;
  final double monthlyFuelCost;
  final double monthlyOperatingCost;
  final double monthlyProfit;
  final double profitMargin;
  final double roi;
  final double? breakEvenMonths;
  final double profitabilityScore;
  final String profitabilityCategory;
  final String recommendation;
  final String explanation;
  final DateTime createdAt;
  final DateTime updatedAt;

  const BusinessEvaluation({
    required this.id,
    required this.userId,
    required this.stationName,
    required this.fuelPrice,
    required this.fuelPurchaseCost,
    required this.dailyCustomers,
    required this.averageLitres,
    required this.monthlyRental,
    required this.monthlyStaffSalary,
    required this.monthlyUtilities,
    required this.monthlyMaintenance,
    required this.monthlyOtherCost,
    required this.initialInvestment,
    required this.monthlySalesVolume,
    required this.monthlyRevenue,
    required this.monthlyFuelCost,
    required this.monthlyOperatingCost,
    required this.monthlyProfit,
    required this.profitMargin,
    required this.roi,
    required this.breakEvenMonths,
    required this.profitabilityScore,
    required this.profitabilityCategory,
    required this.recommendation,
    required this.explanation,
    required this.createdAt,
    required this.updatedAt,
  });

  factory BusinessEvaluation.fromMap(
      Map<String, dynamic> map,
      ) {
    final breakEvenValue = map['break_even_months'];

    return BusinessEvaluation(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      stationName: map['station_name'] as String,
      fuelPrice: (map['fuel_price'] as num).toDouble(),
      fuelPurchaseCost:
      (map['fuel_purchase_cost'] as num).toDouble(),
      dailyCustomers: map['daily_customers'] as int,
      averageLitres:
      (map['average_litres'] as num).toDouble(),
      monthlyRental:
      (map['monthly_rental'] as num).toDouble(),
      monthlyStaffSalary:
      (map['monthly_staff_salary'] as num).toDouble(),
      monthlyUtilities:
      (map['monthly_utilities'] as num).toDouble(),
      monthlyMaintenance:
      (map['monthly_maintenance'] as num).toDouble(),
      monthlyOtherCost:
      (map['monthly_other_cost'] as num).toDouble(),
      initialInvestment:
      (map['initial_investment'] as num).toDouble(),
      monthlySalesVolume:
      (map['monthly_sales_volume'] as num).toDouble(),
      monthlyRevenue:
      (map['monthly_revenue'] as num).toDouble(),
      monthlyFuelCost:
      (map['monthly_fuel_cost'] as num).toDouble(),
      monthlyOperatingCost:
      (map['monthly_operating_cost'] as num).toDouble(),
      monthlyProfit:
      (map['monthly_profit'] as num).toDouble(),
      profitMargin:
      (map['profit_margin'] as num).toDouble(),
      roi: (map['roi'] as num).toDouble(),
      breakEvenMonths: breakEvenValue == null
          ? null
          : (breakEvenValue as num).toDouble(),
      profitabilityScore:
      (map['profitability_score'] as num).toDouble(),
      profitabilityCategory:
      map['profitability_category'] as String,
      recommendation: map['recommendation'] as String,
      explanation: map['explanation'] as String,
      createdAt: DateTime.parse(
        map['created_at'] as String,
      ),
      updatedAt: DateTime.parse(
        map['updated_at'] as String,
      ),
    );
  }
}