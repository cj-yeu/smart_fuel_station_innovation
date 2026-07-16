class Vehicle {
  final String id;
  final String userId;
  final String plateNumber;
  final String vehicleType;
  final String vehicleModel;
  final String fuelType;
  final int registrationYear;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Vehicle({
    required this.id,
    required this.userId,
    required this.plateNumber,
    required this.vehicleType,
    required this.vehicleModel,
    required this.fuelType,
    required this.registrationYear,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Vehicle.fromMap(Map<String, dynamic> map) {
    return Vehicle(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      plateNumber: map['plate_number'] as String,
      vehicleType: map['vehicle_type'] as String,
      vehicleModel: map['vehicle_model'] as String,
      fuelType: map['fuel_type'] as String,
      registrationYear: map['registration_year'] as int,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'plate_number': plateNumber,
      'vehicle_type': vehicleType,
      'vehicle_model': vehicleModel,
      'fuel_type': fuelType,
      'registration_year': registrationYear,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}