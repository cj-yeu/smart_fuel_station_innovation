class NearbyFuelStation {
  static final RegExp _osmIdPattern = RegExp(r'^[1-9][0-9]*$');

  final String osmType;
  final String osmId;
  final String? name;
  final String? brand;
  final String? operatorName;
  final double latitude;
  final double longitude;
  final double distanceKm;

  NearbyFuelStation({
    required this.osmType,
    required this.osmId,
    required this.name,
    required this.brand,
    required this.operatorName,
    required this.latitude,
    required this.longitude,
    required this.distanceKm,
  }) {
    if (!const {'node', 'way', 'relation'}.contains(osmType)) {
      throw ArgumentError.value(osmType, 'osmType', 'Unsupported OSM type.');
    }
    if (!_osmIdPattern.hasMatch(osmId)) {
      throw ArgumentError.value(osmId, 'osmId', 'OSM ID must be canonical.');
    }
    if (!latitude.isFinite || latitude < -90 || latitude > 90) {
      throw ArgumentError.value(latitude, 'latitude', 'Invalid latitude.');
    }
    if (!longitude.isFinite || longitude < -180 || longitude > 180) {
      throw ArgumentError.value(longitude, 'longitude', 'Invalid longitude.');
    }
    if (!distanceKm.isFinite || distanceKm < 0) {
      throw ArgumentError.value(
        distanceKm,
        'distanceKm',
        'Distance must be finite and non-negative.',
      );
    }
  }

  factory NearbyFuelStation.fromMap(Map<String, dynamic> row) {
    return NearbyFuelStation(
      osmType: _requiredString(row['osm_type'], 'osm_type'),
      osmId: _requiredString(row['osm_id'], 'osm_id'),
      name: _nullableString(row['name'], 'name'),
      brand: _nullableString(row['brand'], 'brand'),
      operatorName: _nullableString(row['operator'], 'operator'),
      latitude: _requiredDouble(row['latitude'], 'latitude'),
      longitude: _requiredDouble(row['longitude'], 'longitude'),
      distanceKm: _requiredDouble(row['distance_km'], 'distance_km'),
    );
  }

  static String _requiredString(Object? value, String fieldName) {
    if (value is String && value.isNotEmpty) return value;
    throw FormatException('Nearby fuel station $fieldName must be a string.');
  }

  static String? _nullableString(Object? value, String fieldName) {
    if (value == null || value is String) return value as String?;
    throw FormatException('Nearby fuel station $fieldName must be a string.');
  }

  static double _requiredDouble(Object? value, String fieldName) {
    if (value is num && value.toDouble().isFinite) return value.toDouble();
    throw FormatException('Nearby fuel station $fieldName must be finite.');
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is NearbyFuelStation &&
            osmType == other.osmType &&
            osmId == other.osmId &&
            name == other.name &&
            brand == other.brand &&
            operatorName == other.operatorName &&
            latitude == other.latitude &&
            longitude == other.longitude &&
            distanceKm == other.distanceKm;
  }

  @override
  int get hashCode => Object.hash(
    osmType,
    osmId,
    name,
    brand,
    operatorName,
    latitude,
    longitude,
    distanceKm,
  );
}
