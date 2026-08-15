class FuelCompany {
  final String id;
  final String companyCode;
  final String companyName;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  const FuelCompany({
    required this.id,
    required this.companyCode,
    required this.companyName,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  factory FuelCompany.fromMap(Map<String, dynamic> map) {
    return FuelCompany(
      id: map['id'] as String,
      companyCode: map['company_code'] as String,
      companyName: map['company_name'] as String,
      isActive: map['is_active'] as bool,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
