import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EditProfileScreen extends StatefulWidget {
  final String fullName;
  final String phone;

  const EditProfileScreen({
    super.key,
    required this.fullName,
    required this.phone,
  });

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController fullNameController;
  late final TextEditingController phoneController;

  bool isSaving = false;

  @override
  void initState() {
    super.initState();

    fullNameController = TextEditingController(
      text: widget.fullName,
    );

    phoneController = TextEditingController(
      text: widget.phone,
    );
  }

  Future<void> saveProfile() async {
    final user = Supabase.instance.client.auth.currentUser;
    final fullName = fullNameController.text.trim();
    final phone = phoneController.text.trim();

    if (user == null) {
      showMessage('No logged-in user found', isError: true);
      return;
    }

    if (fullName.isEmpty) {
      showMessage('Full name cannot be empty', isError: true);
      return;
    }

    setState(() {
      isSaving = true;
    });

    try {
      await Supabase.instance.client
          .from('profiles')
          .update({
        'full_name': fullName,
        'phone': phone.isEmpty ? null : phone,
        'updated_at': DateTime.now().toIso8601String(),
      })
          .eq('user_id', user.id);

      await Supabase.instance.client.auth.updateUser(
        UserAttributes(
          data: {
            'full_name': fullName,
          },
        ),
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile updated successfully'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pop(context, true);
    } on AuthException catch (error) {
      if (!mounted) return;
      showMessage(error.message, isError: true);
    } catch (error) {
      if (!mounted) return;
      showMessage(
        'Unable to update profile. Please try again.',
        isError: true,
      );
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
      backgroundColor: const Color(0xFFF4F7F6),
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
              child: Icon(
                Icons.edit,
                size: 46,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 30),
            TextField(
              controller: fullNameController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Full Name',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
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
                  : const Text(
                'Save Changes',
                style: TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}