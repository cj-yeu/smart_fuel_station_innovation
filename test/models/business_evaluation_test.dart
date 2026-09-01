import 'package:flutter_test/flutter_test.dart';
import 'package:smart_fuel_station_innovation/models/business_evaluation.dart';
import 'package:smart_fuel_station_innovation/services/business_evaluation_service.dart';

void main() {
  test(
    'reconstructs a saved result from the narrow id and updated_at response',
    () {
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
      final updatedAt = DateTime.parse('2026-08-31T12:00:00.000Z');

      final evaluation = BusinessEvaluation.fromCalculatedValues(
        id: '123e4567-e89b-12d3-a456-426614174000',
        userId: '123e4567-e89b-12d3-a456-426614174001',
        stationName: 'Saved Station',
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
        createdAt: updatedAt,
        updatedAt: updatedAt,
      );

      expect(evaluation.id, '123e4567-e89b-12d3-a456-426614174000');
      expect(evaluation.updatedAt, updatedAt);
      expect(evaluation.monthlyProfit, result.monthlyProfit);
      expect(evaluation.recommendation, result.recommendation);
    },
  );
}
