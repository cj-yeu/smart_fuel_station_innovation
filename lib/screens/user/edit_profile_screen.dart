import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/profile_service.dart';

class EditProfileScreen extends StatefulWidget {
  final String fullName;
  final String phone;
  final ProfileService? profileService;

  const EditProfileScreen({
    super.key,
    required this.fullName,
    required this.phone,
    this.profileService,
  });

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final ProfileService profileService;
  late final TextEditingController fullNameController;
  late final TextEditingController phoneController;

  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    profileService = widget.profileService ?? ProfileService();

    fullNameController = TextEditingController(text: widget.fullName);

    phoneController = TextEditingController(text: widget.phone);
  }

  Future<void> saveProfile() async {
    if (isSaving) return;

    final fullName = fullNameController.text.trim();
    final phone = phoneController.text.trim();

    if (fullName.isEmpty) {
      showMessage('Full name cannot be empty', isError: true);
      return;
    }

    setState(() {
      isSaving = true;
    });

    try {
      await profileService.updateCurrentProfile(
        fullName: fullName,
        phone: phone.isEmpty ? null : phone,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile updated successfully'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      showMessage('Unable to update profile. Please try again.', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          isSaving = false;
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
    fullNameController.dispose();
    phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Edit Profile'),
        backgroundColor: const Color(0xFF168C4B),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const CircleAvatar(
              radius: 44,
              backgroundColor: Color(0xFF168C4B),
              child: Icon(Icons.edit, size: 46, color: Colors.white),
            ),
            const SizedBox(height: 30),
            TextField(
              controller: fullNameController,
              textInputAction: TextInputAction.next,
              inputFormatters: [LengthLimitingTextInputFormatter(100)],
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
              decoration: const InputDecoration(
                labelText: 'Full Name',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
              decoration: const InputDecoration(
                labelText: 'Phone Number',
                prefixIcon: Icon(Icons.phone_outlined),
                hintText: 'Example: 0123456789',
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: isSaving ? null : saveProfile,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: const Color(0xFF168C4B),
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.green.shade200,
              ),
              child: isSaving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Save Changes', style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}
