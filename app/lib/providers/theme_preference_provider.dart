import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kThemeModeKey = 'app_theme_mode';

/// Supported theme modes for the app.
enum AppThemeMode { auto, dark, light, highContrast }

class ThemePreferenceNotifier extends Notifier<AppThemeMode> {
  bool _hydratedFromPrefs = false;

  @override
  AppThemeMode build() {
    if (!_hydratedFromPrefs) {
      _hydratedFromPrefs = true;
      unawaited(_loadSaved());
    }
    return AppThemeMode.auto; // default until prefs load
  }

  Future<void> _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kThemeModeKey);
    final mode = _parse(saved);
    if (mode != state) state = mode;
  }

  Future<void> setThemeMode(AppThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeModeKey, mode.name);
  }

  static AppThemeMode _parse(String? raw) {
    return switch (raw) {
      'auto' => AppThemeMode.auto,
      'light' => AppThemeMode.light,
      'dark' => AppThemeMode.dark,
      'highContrast' => AppThemeMode.highContrast,
      // Migrate legacy 'system' value to 'auto'
      'system' => AppThemeMode.auto,
      _ => AppThemeMode.auto,
    };
  }
}

final themePreferenceProvider =
    NotifierProvider<ThemePreferenceNotifier, AppThemeMode>(
      ThemePreferenceNotifier.new,
    );
