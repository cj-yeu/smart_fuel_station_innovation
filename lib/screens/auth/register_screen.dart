import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/fuel_company.dart';
import '../../services/profile_service.dart';

class RegisterScreen extends StatefulWidget {
  final ProfileService? profileService;

  const RegisterScreen({super.key, this.profileService});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final formKey = GlobalKey<FormState>();
  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  late final ProfileService profileService;

  List<FuelCompany> companies = const [];
  FuelCompany? selectedCompany;
  String? companyLoadError;
  bool isLoadingCompanies = true;
  bool isCompanyLoadInProgress = false;
  bool isLoading = false;
  int companyLoadVersion = 0;

  bool get canRegister =>
      !isLoading &&
      !isLoadingCompanies &&
      companyLoadError == null &&
      companies.isNotEmpty;

  @override
  void initState() {
    super.initState();
    profileService = widget.profileService ?? ProfileService();
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
      FuelCompany? reloadedSelection;

      if (selectedCompanyCode != null) {
        for (final company in activeCompanies) {
          if (company.companyCode == selectedCompanyCode) {
            reloadedSelection = company;
            break;
          }
        }
      }

      setState(() {
        companies = activeCompanies;
        selectedCompany = reloadedSelection;
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

  Future<void> register() async {
    if (isLoading || isCompanyLoadInProgress) return;

    final name = nameController.text.trim();
    final email = emailController.text.trim();
    final password = passwordController.text;

    if (name.isEmpty || email.isEmpty || password.isEmpty) {
      showMessage('Please fill in all fields', isError: true);
      return;
    }

    if (!email.contains('@')) {
      showMessage('Please enter a valid email address', isError: true);
      return;
    }

    if (password.length < 6) {
      showMessage('Password must contain at least 6 characters', isError: true);
      return;
    }

    if (isLoadingCompanies || companyLoadError != null || companies.isEmpty) {
      showMessage(
        'Load the active fuel-company list before registering.',
        isError: true,
      );
      return;
    }

    final isFormValid = formKey.currentState?.validate() ?? false;
    final company = selectedCompany;

    if (!isFormValid || company == null) return;

    setState(() {
      isLoading = true;
    });

    try {
      await Supabase.instance.client.auth.signUp(
        email: email,
        password: password,
        emailRedirectTo: 'io.smartfuelstation.app://login-callback/',
        data: {
          'full_name': name,
          'requested_company_code': company.companyCode,
        },
      );

      if (!mounted) return;

      showMessage(
        'Registration successful. Verify your email, then sign in to confirm your company with an invitation code.',
      );

      Navigator.pop(context);
    } on AuthException catch (error) {
      if (!mounted) return;
      showMessage(error.message, isError: true);
    } catch (error) {
      if (!mounted) return;
      showMessage('Unable to register. Please try again.', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  void showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F6),
      appBar: AppBar(
        title: const Text('Create Account'),
        backgroundColor: const Color(0xFF168C4B),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Form(
                key: formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(
                      Icons.person_add,
                      size: 70,
                      color: Color(0xFF168C4B),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Register',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 30),
                    TextField(
                      controller: nameController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Full Name',
                        prefixIcon: Icon(Icons.person),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email),
                      ),
                    ),
                    const SizedBox(height: 16),
                    buildCompanyField(),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F5EC),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline, color: Color(0xFF168C4B)),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Your selection is a registration preference only. Verify your email, sign in, and use your company invitation code to gain access.',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: passwordController,
                      obscureText: true,
                      onSubmitted: (_) {
                        if (canRegister) register();
                      },
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        prefixIcon: Icon(Icons.lock),
                        helperText: 'Minimum 6 characters',
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: canRegister ? register : null,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: const Color(0xFF168C4B),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.green.shade200,
                      ),
                      child: isLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Register',
                              style: TextStyle(fontSize: 16),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget buildCompanyField() {
    if (isLoadingCompanies) {
      return const InputDecorator(
        decoration: InputDecoration(
          labelText: 'Fuel Company',
          prefixIcon: Icon(Icons.local_gas_station_outlined),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('Loading active companies...'),
          ],
        ),
      );
    }

    if (companyLoadError != null) {
      return buildCompanyLoadState(
        message: companyLoadError!,
        buttonLabel: 'Try Again',
      );
    }

    if (companies.isEmpty) {
      return buildCompanyLoadState(
        message: 'No active fuel companies are available.',
        buttonLabel: 'Reload',
      );
    }

    return DropdownButtonFormField<FuelCompany>(
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
              child: Text(
                '${company.companyName} (${company.companyCode})',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(growable: false),
      onChanged: isLoading
          ? null
          : (company) {
              setState(() {
                selectedCompany = company;
              });
            },
      validator: (company) {
        if (company == null) {
          return 'Please select your fuel company';
        }
        return null;
      },
    );
  }

  Widget buildCompanyLoadState({
    required String message,
    required String buttonLabel,
  }) {
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Fuel Company',
        prefixIcon: Icon(Icons.local_gas_station_outlined),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(message, style: const TextStyle(color: Colors.red)),
          ),
          TextButton(onPressed: loadCompanies, child: Text(buttonLabel)),
        ],
      ),
    );
  }
}
