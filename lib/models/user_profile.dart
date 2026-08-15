import 'fuel_company.dart';

class UserProfile {
  final String id;
  final String userId;
  final String? fullName;
  final String? email;
  final String? phone;
  final String role;
  final String? companyId;
  final FuelCompany? company;
  final DateTime createdAt;
  final DateTime updatedAt;

  const UserProfile({
    required this.id,
    required this.userId,
    required this.fullName,
    required this.email,
    required this.phone,
    required this.role,
    required this.companyId,
    required this.company,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get hasCompany => companyId != null;

  bool get isCompanyAdmin => role == 'company_admin';

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    final companyData = map['fuel_companies'];
    final company = companyData == null
        ? null
        : FuelCompany.fromMap(Map<String, dynamic>.from(companyData as Map));

    return UserProfile(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      fullName: map['full_name'] as String?,
      email: map['email'] as String?,
      phone: map['phone'] as String?,
      role: map['role'] as String,
      companyId: map['company_id'] as String?,
      company: company,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
