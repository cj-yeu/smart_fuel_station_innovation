import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/official_fuel_price.dart';

typedef OfficialFuelPriceHttpGetter = Future<http.Response> Function(Uri uri);

class OfficialFuelPriceUnavailableException implements Exception {
  const OfficialFuelPriceUnavailableException();

  @override
  String toString() => 'Official fuel price is currently unavailable.';
}

/// Loads the latest official weekly fuel price without sending user data.
///
/// A repository instance keeps one successful response in memory for the
/// lifetime of its owning screen, including product changes and retries.
class OfficialFuelPriceRepository {
  static final Uri latestPriceUri = Uri.parse(
    'https://api.data.gov.my/data-catalogue?'
    'id=fuelprice&filter=level@series_type&sort=-date&limit=1',
  );

  final OfficialFuelPriceHttpGetter _httpGetter;
  OfficialFuelPrice? _cachedPrice;
  Future<OfficialFuelPrice>? _loadingPrice;

  OfficialFuelPriceRepository({OfficialFuelPriceHttpGetter? httpGetter})
    : _httpGetter = httpGetter ?? http.get;

  Future<OfficialFuelPrice> loadLatest() {
    final cachedPrice = _cachedPrice;
    if (cachedPrice != null) return Future.value(cachedPrice);

    return _loadingPrice ??= _loadAndCache();
  }

  Future<OfficialFuelPrice> _loadAndCache() async {
    try {
      final response = await _httpGetter(latestPriceUri).timeout(
        const Duration(seconds: 8),
      );
      if (response.statusCode != 200) {
        throw const OfficialFuelPriceUnavailableException();
      }

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final price = OfficialFuelPrice.fromApiResponse(decoded);
      _cachedPrice = price;
      return price;
    } catch (_) {
      throw const OfficialFuelPriceUnavailableException();
    } finally {
      _loadingPrice = null;
    }
  }
}
