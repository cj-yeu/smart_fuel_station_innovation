import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppThemeController extends ChangeNotifier {
  static const _preferenceKey = 'app_theme_mode';

  final SharedPreferences _preferences;
  ThemeMode _themeMode;

  AppThemeController._(this._preferences, this._themeMode);

  ThemeMode get themeMode => _themeMode;

  static Future<AppThemeController> create() async {
    final preferences = await SharedPreferences.getInstance();
    return AppThemeController._(
      preferences,
      _themeModeFromPreference(preferences.getString(_preferenceKey)),
    );
  }

  Future<void> setThemeMode(ThemeMode value) async {
    if (_themeMode == value) return;
    _themeMode = value;
    notifyListeners();
    await _preferences.setString(_preferenceKey, value.name);
  }

  /// Switches directly between the two explicit modes. If the first launch
  /// follows the device setting, its current brightness determines the next
  /// mode so one tap always produces a visible change.
  Future<void> toggleLightDark(Brightness currentBrightness) {
    return setThemeMode(
      currentBrightness == Brightness.dark ? ThemeMode.light : ThemeMode.dark,
    );
  }

  static ThemeMode _themeModeFromPreference(String? value) => switch (value) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };
}

class AppThemeScope extends InheritedNotifier<AppThemeController> {
  const AppThemeScope({
    super.key,
    required AppThemeController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppThemeController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppThemeScope>();
    assert(scope != null, 'AppThemeScope is missing from the widget tree.');
    return scope!.notifier!;
  }
}
