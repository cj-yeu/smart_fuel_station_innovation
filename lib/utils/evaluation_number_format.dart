import 'package:intl/intl.dart';

/// Consistent, presentation-only formatting for Module 3 figures.
///
/// Invalid values are rejected instead of being rendered as `NaN`, infinity,
/// or a fabricated zero. Editable field values intentionally do not use this
/// formatter so they remain directly parseable by the existing form logic.
abstract final class EvaluationNumberFormat {
  static final NumberFormat _currency = NumberFormat('#,##0.00', 'en_US');
  static final NumberFormat _wholeNumber = NumberFormat('#,##0', 'en_US');
  static final NumberFormat _oneDecimal = NumberFormat('#,##0.0', 'en_US');
  static final NumberFormat _twoDecimals = NumberFormat('#,##0.00', 'en_US');
  static final NumberFormat _compactThousands = NumberFormat('0.##', 'en_US');
  static final NumberFormat _compactMillions = NumberFormat('0.00', 'en_US');
  static final NumberFormat _compactBillions = NumberFormat('0.00', 'en_US');

  static String currency(num value) {
    final finiteValue = _requireFinite(value);
    final prefix = finiteValue < 0 ? '-RM ' : 'RM ';
    return '$prefix${_currency.format(finiteValue.abs())}';
  }

  static String wholeNumber(num value) {
    return _wholeNumber.format(_requireFinite(value));
  }

  static String volumeLitres(num value) => '${wholeNumber(value)} L';

  static String percentage(num value) {
    return '${_twoDecimals.format(_requireFinite(value))}%';
  }

  static String scoreValue(num value) =>
      _oneDecimal.format(_requireFinite(value));

  static String score(num value) => '${scoreValue(value)}/100';

  static String breakEvenMonths(
    num? value, {
    String unavailable = 'Not currently profitable',
  }) {
    if (value == null) return unavailable;
    return '${_oneDecimal.format(_requireFinite(value))} months';
  }

  /// Compact labels are limited to chart axes; detailed values use [currency].
  static String compactCurrency(num value) {
    final finiteValue = _requireFinite(value);
    final absoluteValue = finiteValue.abs();
    final prefix = finiteValue < 0 ? '-RM ' : 'RM ';

    if (absoluteValue >= 1000000000) {
      return '$prefix${_compactBillions.format(absoluteValue / 1000000000)}B';
    }
    if (absoluteValue >= 1000000) {
      return '$prefix${_compactMillions.format(absoluteValue / 1000000)}M';
    }
    if (absoluteValue >= 1000) {
      return '$prefix${_compactThousands.format(absoluteValue / 1000)}K';
    }
    return currency(finiteValue);
  }

  static double _requireFinite(num value) {
    final finiteValue = value.toDouble();
    if (!finiteValue.isFinite) {
      throw ArgumentError.value(
        value,
        'value',
        'Evaluation display values must be finite.',
      );
    }
    return finiteValue;
  }
}
