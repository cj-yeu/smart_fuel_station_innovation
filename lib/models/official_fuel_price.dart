/// The supported official weekly retail products for this East Malaysia app.
enum OfficialFuelProduct {
  ron95('RON95'),
  ron97('RON97'),
  dieselEastMalaysia('Diesel — East Malaysia');

  const OfficialFuelProduct(this.displayLabel);

  final String displayLabel;

  double priceFrom(OfficialFuelPrice price) {
    return switch (this) {
      OfficialFuelProduct.ron95 => price.ron95,
      OfficialFuelProduct.ron97 => price.ron97,
      OfficialFuelProduct.dieselEastMalaysia => price.dieselEastMalaysia,
    };
  }
}

/// One latest weekly retail-price record returned by data.gov.my.
class OfficialFuelPrice {
  final DateTime effectiveDate;
  final double ron95;
  final double ron97;
  final double dieselEastMalaysia;

  const OfficialFuelPrice({
    required this.effectiveDate,
    required this.ron95,
    required this.ron97,
    required this.dieselEastMalaysia,
  });

  double priceFor(OfficialFuelProduct product) => product.priceFrom(this);

  /// Parses only the exact single latest `level` record requested by the
  /// repository. Invalid provider data remains an internal parse failure.
  factory OfficialFuelPrice.fromApiResponse(Object? response) {
    if (response is! List || response.length != 1 || response.single is! Map) {
      throw const FormatException('Official fuel-price response is invalid.');
    }

    final record = Map<Object?, Object?>.from(response.single as Map);
    if (record['series_type'] != 'level') {
      throw const FormatException('Official fuel-price series is invalid.');
    }

    final dateValue = record['date'];
    final effectiveDate = dateValue is String
        ? DateTime.tryParse(dateValue)
        : null;
    if (effectiveDate == null) {
      throw const FormatException('Official fuel-price date is invalid.');
    }

    return OfficialFuelPrice(
      effectiveDate: effectiveDate,
      ron95: _requiredPrice(record, 'ron95'),
      ron97: _requiredPrice(record, 'ron97'),
      dieselEastMalaysia: _requiredPrice(record, 'diesel_eastmsia'),
    );
  }

  static double _requiredPrice(Map<Object?, Object?> record, String field) {
    final value = record[field];
    if (value is! num) {
      throw FormatException('Official fuel-price $field is invalid.');
    }

    final price = value.toDouble();
    if (!price.isFinite || price <= 0) {
      throw FormatException('Official fuel-price $field is invalid.');
    }
    return price;
  }
}
