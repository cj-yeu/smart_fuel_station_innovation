import 'package:flutter/material.dart';

import '../../models/user_profile.dart';
import '../../services/profile_service.dart';
import 'edit_profile_screen.dart';

class ProfileScreen extends StatefulWidget {
  final ProfileService? profileService;

  const ProfileScreen({super.key, this.profileService});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final ProfileService profileService;

  UserProfile? profile;
  bool isLoading = true;
  bool isLoadingProfile = false;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    profileService = widget.profileService ?? ProfileService();
    loadProfile();
  }

  Future<void> loadProfile({bool showLoading = false}) async {
    if (isLoadingProfile) return;

    isLoadingProfile = true;

    if (showLoading && mounted) {
      setState(() {
        isLoading = true;
        errorMessage = null;
      });
    }

    try {
      final loadedProfile = await profileService.fetchCurrentProfile();

      if (!mounted) return;

      setState(() {
        profile = loadedProfile;
        isLoading = false;
        errorMessage = null;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        isLoading = false;
        errorMessage = 'Unable to load profile. Please try again.';
      });
    } finally {
      isLoadingProfile = false;
    }
  }

  String displayValue(String? value, {required String fallback}) {
    final normalizedValue = value?.trim();
    return normalizedValue == null || normalizedValue.isEmpty
        ? fallback
        : normalizedValue;
  }

  String displayRole(String role) {
    switch (role) {
      case 'company_user':
        return 'Company User';
      case 'company_admin':
        return 'Company Admin';
      default:
        final words = role
            .trim()
            .split(RegExp(r'[_\s-]+'))
            .where((word) => word.isNotEmpty)
            .map(
              (word) =>
                  '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}',
            )
            .toList();
        return words.isEmpty ? 'Not provided' : words.join(' ');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('My Profile'),
        backgroundColor: const Color(0xFF168C4B),
        foregroundColor: Colors.white,
      ),
      body: buildBody(),
    );
  }

  Widget buildBody() {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 60, color: Colors.red),
              const SizedBox(height: 16),
              Text(errorMessage!),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => loadProfile(showLoading: true),
                child: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    final loadedProfile = profile;
    if (loadedProfile == null) {
      return const Center(child: Text('Unable to load profile.'));
    }

    final fullName = displayValue(
      loadedProfile.fullName,
      fallback: 'Not provided',
    );
    final email = displayValue(loadedProfile.email, fallback: 'Not provided');
    final phone = displayValue(loadedProfile.phone, fallback: 'Not provided');
    final company = loadedProfile.company;
    final companyName = loadedProfile.companyId == null
        ? 'Not assigned'
        : company == null
        ? 'Company information unavailable'
        : displayValue(company.companyName, fallback: 'Not assigned');
    final companyCode = company == null
        ? 'Not available'
        : displayValue(company.companyCode, fallback: 'Not available');
    final role = displayRole(loadedProfile.role);

    return RefreshIndicator(
      onRefresh: loadProfile,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const CircleAvatar(
            radius: 48,
            backgroundColor: Color(0xFF168C4B),
            child: Icon(Icons.person, size: 56, color: Colors.white),
          ),
          const SizedBox(height: 16),
          Text(
            fullName,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            email,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 30),
          profileTile(
            icon: Icons.person_outline,
            title: 'Full Name',
            value: fullName,
          ),
          profileTile(icon: Icons.email_outlined, title: 'Email', value: email),
          profileTile(icon: Icons.phone_outlined, title: 'Phone', value: phone),
          const SizedBox(height: 8),
          const Text(
            'Company Membership',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF168C4B),
            ),
          ),
          const SizedBox(height: 10),
          companyMembershipCard(
            companyName: companyName,
            companyCode: companyCode,
            role: role,
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: () async {
              final updated = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (context) => EditProfileScreen(
                    fullName: loadedProfile.fullName ?? '',
                    phone: loadedProfile.phone ?? '',
                  ),
                ),
              );

              if (!mounted) return;

              if (updated == true) {
                await loadProfile(showLoading: true);
              }
            },
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: const Color(0xFF168C4B),
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.edit),
            label: const Text('Edit Profile', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }

  Widget companyMembershipCard({
    required String companyName,
    required String companyCode,
    required String role,
  }) {
    return Card(
      color: const Color(0xFFE8F5EE),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CircleAvatar(
              backgroundColor: Color(0xFF168C4B),
              foregroundColor: Colors.white,
              child: Icon(Icons.local_gas_station),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'User → Fuel Company',
                    style: TextStyle(
                      color: Color(0xFF168C4B),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    companyName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  membershipDetail(label: 'Company Code', value: companyCode),
                  const SizedBox(height: 6),
                  membershipDetail(label: 'Role', value: role),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget membershipDetail({required String label, required String value}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 112,
          child: Text(label, style: const TextStyle(color: Colors.black54)),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }

  Widget profileTile({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF168C4B)),
        title: Text(title),
        subtitle: Text(
          value,
          style: const TextStyle(fontSize: 16, color: Colors.black87),
        ),
      ),
    );
  }
}
