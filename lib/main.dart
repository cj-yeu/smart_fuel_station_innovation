import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/auth/auth_profile_gate.dart';
import 'services/app_theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://xgjulojahmuibitvuews.supabase.co',
    publishableKey: 'sb_publishable_VeDvKU-8iRkb7xv14VlQIg_qNKaXwJ1',
  );

  final themeController = await AppThemeController.create();
  runApp(SmartFuelApp(themeController: themeController));
}

class SmartFuelApp extends StatelessWidget {
  final AppThemeController themeController;

  const SmartFuelApp({super.key, required this.themeController});

  @override
  Widget build(BuildContext context) {
    return AppThemeScope(
      controller: themeController,
      child: ListenableBuilder(
        listenable: themeController,
        builder: (context, _) => MaterialApp(
          title: 'Smart Fuel Station Innovation',
          debugShowCheckedModeBanner: false,
          themeMode: themeController.themeMode,
          theme: _buildTheme(Brightness.light),
          darkTheme: _buildTheme(Brightness.dark),
          home: const AuthProfileGate(),
        ),
      ),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF168C4B),
        brightness: brightness,
      ),
      scaffoldBackgroundColor: isDark
          ? const Color(0xFF121715)
          : const Color(0xFFF5F8F6),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF1D2621) : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: isDark ? const Color(0xFF415148) : const Color(0xFFDCE5DF),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF168C4B), width: 2),
        ),
      ),
    );
  }
}
