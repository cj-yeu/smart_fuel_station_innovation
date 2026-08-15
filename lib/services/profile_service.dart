import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/fuel_company.dart';
import '../models/user_profile.dart';

class ProfileService {
  static const String _companySelect =
      'id,company_code,company_name,is_active,created_at,updated_at';

  static const String _profileSelect =
      'id,user_id,full_name,email,phone,role,company_id,created_at,updated_at,'
      'fuel_companies!profiles_company_id_fkey('
      'id,company_code,company_name,is_active,created_at,updated_at'
      ')';

  final SupabaseClient _client;

  ProfileService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  Future<List<FuelCompany>> fetchActiveCompanies() async {
    final data = await _client
        .from('fuel_companies')
        .select(_companySelect)
        .eq('is_active', true)
        .order('company_name');

    return data
        .map((item) => FuelCompany.fromMap(item))
        .toList(growable: false);
  }

  Future<UserProfile> fetchCurrentProfile() async {
    final user = _requireCurrentUser();

    final data = await _client
        .from('profiles')
        .select(_profileSelect)
        .eq('user_id', user.id)
        .single();

    return UserProfile.fromMap(data);
  }

  Future<UserProfile> claimCompanyMembership({
    required String companyCode,
    required String invitationCode,
  }) async {
    _requireCurrentUser();

    final normalizedCompanyCode = companyCode.trim();
    final normalizedInvitationCode = invitationCode.trim();

    if (normalizedCompanyCode.isEmpty) {
      throw ArgumentError('Company code cannot be blank.');
    }

    if (normalizedInvitationCode.isEmpty) {
      throw ArgumentError('Invitation code cannot be blank.');
    }

    await _client.rpc(
      'claim_company_membership',
      params: {
        'p_company_code': normalizedCompanyCode,
        'p_invitation_code': normalizedInvitationCode,
      },
    );

    return fetchCurrentProfile();
  }

  Future<void> updateCurrentProfile({
    required String fullName,
    String? phone,
  }) async {
    final user = _requireCurrentUser();
    final normalizedFullName = fullName.trim();
    final normalizedPhone = phone?.trim();

    if (normalizedFullName.isEmpty) {
      throw ArgumentError('Full name cannot be blank.');
    }

    await _client
        .from('profiles')
        .update({
          'full_name': normalizedFullName,
          'phone': normalizedPhone == null || normalizedPhone.isEmpty
              ? null
              : normalizedPhone,
        })
        .eq('user_id', user.id);
  }

  User _requireCurrentUser() {
    final user = _client.auth.currentUser;

    if (user == null) {
      throw StateError('No authenticated user is available.');
    }

    return user;
  }
}
