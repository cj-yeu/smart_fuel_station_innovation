import 'package:flutter_test/flutter_test.dart';
import 'package:smart_fuel_station_innovation/services/business_evaluation_service.dart';

void main() {
  test('calculation explanation uses grouped presentation values', () {
    final result = BusinessEvaluationService.calculate(
      fuelPrice: 3,
      fuelPurchaseCost: 1,
      dailyCustomers: 1000,
      averageLitres: 30,
      monthlyRental: 20000,
      monthlyStaffSalary: 30000,
      monthlyUtilities: 10000,
      monthlyMaintenance: 20000,
      monthlyOtherCost: 20000,
      initialInvestment: 3400000,
    );

    expect(result.monthlySalesVolume, 900000);
    expect(result.monthlyRevenue, 2700000);
    expect(result.monthlyFuelCost, 900000);
    expect(result.monthlyOperatingCost, 1000000);
    expect(result.monthlyProfit, 1700000);
    expect(
      result.explanation,
      'Estimated monthly profit is RM 1,700,000.00, '
      'with a profit margin of 62.96% and an annual ROI of 600.00%. '
      'The estimated break-even period is 2.0 months.',
    );
  });
}
