import 'package:flutter/material.dart';

enum ThemePreference { system, light, dark }

ThemePreference parseThemePreference(String? value) {
  switch ((value ?? '').toLowerCase()) {
    case 'light':
      return ThemePreference.light;
    case 'dark':
      return ThemePreference.dark;
    default:
      return ThemePreference.system;
  }
}

String themePreferenceToString(ThemePreference pref) {
  switch (pref) {
    case ThemePreference.light:
      return 'light';
    case ThemePreference.dark:
      return 'dark';
    case ThemePreference.system:
    default:
      return 'system';
  }
}

class ThemeController extends ChangeNotifier {
  ThemeController._();
  static final ThemeController instance = ThemeController._();

  ThemePreference _preference = ThemePreference.system;
  ThemePreference get preference => _preference;

  ThemeMode get mode {
    switch (_preference) {
      case ThemePreference.light:
        return ThemeMode.light;
      case ThemePreference.dark:
        return ThemeMode.dark;
      case ThemePreference.system:
      default:
        return ThemeMode.system;
    }
  }

  void applyPreference(ThemePreference pref) {
    if (_preference == pref) return;
    _preference = pref;
    notifyListeners();
  }
}
