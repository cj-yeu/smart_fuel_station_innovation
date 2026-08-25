import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/fuel_company.dart';
import '../../services/profile_service.dart';

class CompanyOnboardingScreen extends StatefulWidget {
  final ProfileService? profileService;
  final String? initialCompanyCode;
  final VoidCallback onCompleted;
  final Future<void> Function() onSignOut;

  const CompanyOnboardingScreen({
    super.key,
    this.profileService,
    this.initialCompanyCode,
    required this.onCompleted,
    required this.onSignOut,
  });

  @override
  State<CompanyOnboardingScreen> createState() =>
      _CompanyOnboardingScreenState();
}

class _CompanyOnboardingScreenState extends State<CompanyOnboardingScreen> {
  final formKey = GlobalKey<FormState>();
  final invitationController = TextEditingController();

  late final ProfileService profileService;
  late final String? initialCompanyCode;

  List<FuelCompany> companies = const [];
  FuelCompany? selectedCompany;
  String? companyLoadError;
  String? claimError;
  bool isLoadingCompanies = true;
  bool isCompanyLoadInProgress = false;
  bool isClaiming = false;
  bool isSigningOut = false;
  bool obscureInvitationCode = true;
  int companyLoadVersion = 0;

  @override
  void initState() {
    super.initState();
    profileService = widget.profileService ?? ProfileService();
    initialCompanyCode = normalizeCompanyCode(widget.initialCompanyCode);
    loadCompanies();
  }

  Future<void> loadCompanies() async {
    if (isCompanyLoadInProgress) return;

    final selectedCompanyCode = selectedCompany?.companyCode;

    setState(() {
      isCompanyLoadInProgress = true;
      isLoadingCompanies = true;
      companyLoadError = null;
    });

    try {
      final loadedCompanies = await profileService.fetchActiveCompanies();

      if (!mounted) return;

      final activeCompanies = loadedCompanies
          .where((company) => company.isActive)
          .toList(growable: false);
      final currentSelection = findCompanyByCode(
        activeCompanies,
        selectedCompanyCode,
      );

      // Auth metadata improves onboarding UX only. It does not establish
      // membership; the invitation-code claim RPC remains authoritative.
      final reconciledSelection =
          currentSelection ??
          findCompanyByCode(activeCompanies, initialCompanyCode);

      setState(() {
        companies = activeCompanies;
        selectedCompany = reconciledSelection;
        isLoadingCompanies = false;
        isCompanyLoadInProgress = false;
        companyLoadVersion++;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        companies = const [];
        isLoadingCompanies = false;
        isCompanyLoadInProgress = false;
        companyLoadError =
            'Unable to load fuel companies. Check your connection and try again.';
      });
    }
  }

  String? normalizeCompanyCode(String? companyCode) {
    final normalizedCode = companyCode?.trim().toLowerCase();
    return normalizedCode == null || normalizedCode.isEmpty
        ? null
        : normalizedCode;
  }

  FuelCompany? findCompanyByCode(
    List<FuelCompany> activeCompanies,
    String? companyCode,
  ) {
    final normalizedCode = normalizeCompanyCode(companyCode);
    if (normalizedCode == null) return null;

    for (final company in activeCompanies) {
      if (normalizeCompanyCode(company.companyCode) == normalizedCode) {
        return company;
      }
    }

    return null;
  }

  Future<void> claimMembership() async {
    if (isClaiming || isSigningOut) return;

    final isValid = formKey.currentState?.validate() ?? false;
    final company = selectedCompany;

    if (!isValid || company == null) return;

    final invitationCode = invitationController.text.trim();

    setState(() {
      isClaiming = true;
      claimError = null;
    });

    try {
      final profile = await profileService.claimCompanyMembership(
        companyCode: company.companyCode,
        invitationCode: invitationCode,
      );

      if (!mounted) return;

      invitationController.clear();

      if (!profile.hasCompany) {
        setState(() {
          isClaiming = false;
          claimError = 'Membership could not be confirmed. Please try again.';
        });
        return;
      }

      setState(() {
        isClaiming = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Company membership confirmed.'),
          backgroundColor: Colors.green,
        ),
      );

      widget.onCompleted();
    } catch (error) {
      if (!mounted) return;

      invitationController.clear();

      setState(() {
        isClaiming = false;
        claimError = safeClaimError(error);
      });
    }
  }

  Future<void> signOut() async {
    if (isSigningOut || isClaiming) return;

    setState(() {
      isSigningOut = true;
      claimError = null;
    });

    invitationController.clear();

    try {
      await widget.onSignOut();
    } catch (_) {
      if (!mounted) return;

      setState(() {
        isSigningOut = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to sign out. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String safeClaimError(Object error) {
    if (error is StateError || error is AuthException) {
      return 'Your session is no longer available. Please sign in again.';
    }

    if (error is ArgumentError) {
      return 'Select a company and enter the invitation code provided to you.';
    }

    if (error is PostgrestException) {
      final message = error.message.toLowerCase();

      if (message.contains('already has a company membership')) {
        return 'Your profile already belongs to a fuel company.';
      }

      if (message.contains('active fuel company not found')) {
        return 'The selected company is no longer available. Reload the company list.';
      }

      if (message.contains('authentication') ||
          message.contains('profile is required')) {
        return 'Your account could not be verified. Please sign in again.';
      }

      if (message.contains('invitation') ||
          message.contains('expired') ||
          message.contains('inactive') ||
          message.contains('usage limit')) {
        return 'The invitation code is invalid, inactive, expired, or has no remaining uses.';
      }
    }

    return 'Unable to verify company membership. Check your connection and try again.';
  }

  @override
  void dispose() {
    invitationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Join Your Company'),
        backgroundColor: const Color(0xFF168C4B),
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: 'Sign out',
            onPressed: isClaiming || isSigningOut ? null : signOut,
            icon: isSigningOut
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(child: buildBody()),
    );
  }

  Widget buildBody() {
    if (isLoadingCompanies) {
      return const Center(child: CircularProgressIndicator());
    }

    if (companyLoadError != null) {
      return buildCompanyState(
        icon: Icons.cloud_off_outlined,
        message: companyLoadError!,
        buttonLabel: 'Try Again',
        onPressed: loadCompanies,
      );
    }

    if (companies.isEmpty) {
      return buildCompanyState(
        icon: Icons.business_outlined,
        message:
            'No active fuel companies are available. Contact your company administrator.',
        buttonLabel: 'Reload',
        onPressed: loadCompanies,
      );
    }

    return Form(
      key: formKey,
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(24),
        children: [
          const Icon(
            Icons.business_center_outlined,
            size: 70,
            color: Color(0xFF168C4B),
          ),
          const SizedBox(height: 20),
          const Text(
            'Connect to Your Fuel Company',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Text(
            'Select the company you represent and enter its invitation code to continue.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 32),
          DropdownButtonFormField<FuelCompany>(
            key: ValueKey(companyLoadVersion),
            initialValue: selectedCompany,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Fuel Company',
              prefixIcon: Icon(Icons.local_gas_station_outlined),
            ),
            items: companies
                .map(
                  (company) => DropdownMenuItem<FuelCompany>(
                    value: company,
                    child: Text(company.companyName),
                  ),
                )
                .toList(growable: false),
            onChanged: isClaiming || isSigningOut
                ? null
                : (company) {
                    setState(() {
                      selectedCompany = company;
                      claimError = null;
                    });
                  },
            validator: (company) {
              if (company == null) {
                return 'Please select your fuel company';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: invitationController,
            enabled: !isSigningOut,
            obscureText: obscureInvitationCode,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.done,
            onChanged: (_) {
              if (claimError != null) {
                setState(() {
                  claimError = null;
                });
              }
            },
            onFieldSubmitted: (_) {
              if (!isClaiming && !isSigningOut) claimMembership();
            },
            decoration: InputDecoration(
              labelText: 'Company Invitation Code',
              prefixIcon: const Icon(Icons.key_outlined),
              suffixIcon: IconButton(
                tooltip: obscureInvitationCode ? 'Show code' : 'Hide code',
                onPressed: isClaiming || isSigningOut
                    ? null
                    : () {
                        setState(() {
                          obscureInvitationCode = !obscureInvitationCode;
                        });
                      },
                icon: Icon(
                  obscureInvitationCode
                      ? Icons.visibility_off
                      : Icons.visibility,
                ),
              ),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter your company invitation code';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.security_outlined,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Use only the invitation code supplied by your company administrator. The code is not saved on this device.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (claimError != null) ...[
            const SizedBox(height: 16),
            Text(
              claimError!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: isClaiming || isSigningOut ? null : claimMembership,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: const Color(0xFF168C4B),
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.green.shade200,
            ),
            child: isClaiming
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Join Company', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }

  Widget buildCompanyState({
    required IconData icon,
    required String message,
    required String buttonLabel,
    required VoidCallback onPressed,
  }) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: const Color(0xFF168C4B)),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            ElevatedButton(onPressed: onPressed, child: Text(buttonLabel)),
          ],
        ),
      ),
    );
  }
}
