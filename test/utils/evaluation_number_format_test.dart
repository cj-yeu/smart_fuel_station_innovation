import 'package:flutter_test/flutter_test.dart';
import 'package:smart_fuell_station_innovation/utils/evaluation_number_format.dart';

void main() {
  group('EvaluationNumberFormat', () {
    test('formats grouped positive, negative, and zero currency', () {
      expect(EvaluationNumberFormat.currency(1234567.89), 'RM 1,234,567.89');
      expect(EvaluationNumberFormat.currency(-123456.78), '-RM 123,456.78');
      expect(EvaluationNumberFormat.currency(0), 'RM 0.00');
    });

    test('formats grouped percentages and integer counts', () {
      expect(EvaluationNumberFormat.percentage(1234.56), '1,234.56%');
      expect(EvaluationNumberFormat.wholeNumber(1234567), '1,234,567');
      expect(EvaluationNumberFormat.volumeLitres(1500000), '1,500,000 L');
      expect(EvaluationNumberFormat.score(75), '75.0/100');
      expect(EvaluationNumberFormat.breakEvenMonths(1234.56), '1,234.6 months');
      expect(
        EvaluationNumberFormat.breakEvenMonths(null),
        'Not currently profitable',
      );
    });

    test('formats million and billion detailed currency values', () {
      expect(EvaluationNumberFormat.currency(1500000), 'RM 1,500,000.00');
      expect(
        EvaluationNumberFormat.currency(1250000000),
        'RM 1,250,000,000.00',
      );
    });

    test('formats compact K, M, and B chart-axis labels', () {
      expect(EvaluationNumberFormat.compactCurrency(750000), 'RM 750K');
      expect(EvaluationNumberFormat.compactCurrency(1500000), 'RM 1.50M');
      expect(EvaluationNumberFormat.compactCurrency(1250000000), 'RM 1.25B');
      expect(EvaluationNumberFormat.compactCurrency(-125000), '-RM 125K');
    });

    test('rejects NaN and positive or negative infinity', () {
      for (final value in [
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        final formatters = <String Function(double)>[
          EvaluationNumberFormat.currency,
          EvaluationNumberFormat.wholeNumber,
          EvaluationNumberFormat.volumeLitres,
          EvaluationNumberFormat.percentage,
          EvaluationNumberFormat.score,
          EvaluationNumberFormat.breakEvenMonths,
          EvaluationNumberFormat.compactCurrency,
        ];
        for (final formatter in formatters) {
          expect(() => formatter(value), throwsArgumentError);
        }
      }
    });
  });
}
