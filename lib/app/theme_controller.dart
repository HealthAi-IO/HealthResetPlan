import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemeMode {
  system('system', ThemeMode.system),
  light('light', ThemeMode.light),
  dark('dark', ThemeMode.dark);

  const AppThemeMode(this.key, this.themeMode);

  final String key;
  final ThemeMode themeMode;
}

enum AppColorTheme {
  standard('default', '默认主题', Color(0xFF0B91E5)),
  ocean('ocean', '海洋蓝', Color(0xFF0B67D1)),
  emerald('emerald', '健康绿', Color(0xFF16866A)),
  violet('violet', '沉稳紫', Color(0xFF6D55C5)),
  amber('amber', '暖橙', Color(0xFFC56518));

  const AppColorTheme(this.key, this.label, this.seed);

  final String key;
  final String label;
  final Color seed;
}

class ThemeController extends ChangeNotifier {
  static const _preferenceKey = 'app_color_theme_v1';
  static const _themeModePreferenceKey = 'app_theme_mode_v1';
  static const _darkModePreferenceKey = 'app_dark_mode_v1';

  AppColorTheme _colorTheme = AppColorTheme.standard;
  AppThemeMode _selectedThemeMode = AppThemeMode.system;

  AppColorTheme get colorTheme => _colorTheme;
  AppThemeMode get selectedThemeMode => _selectedThemeMode;
  ThemeMode get themeMode => _selectedThemeMode.themeMode;
  bool get darkMode {
    return switch (_selectedThemeMode) {
      AppThemeMode.system =>
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark,
      AppThemeMode.light => false,
      AppThemeMode.dark => true,
    };
  }

  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    final saved = preferences.getString(_preferenceKey);
    final savedThemeMode = preferences.getString(_themeModePreferenceKey);
    _selectedThemeMode = AppThemeMode.values.firstWhere(
      (item) => item.key == savedThemeMode,
      orElse: () => AppThemeMode.system,
    );
    if (savedThemeMode == null &&
        preferences.containsKey(_darkModePreferenceKey)) {
      _selectedThemeMode = preferences.getBool(_darkModePreferenceKey) == true
          ? AppThemeMode.dark
          : AppThemeMode.light;
      await preferences.setString(
        _themeModePreferenceKey,
        _selectedThemeMode.key,
      );
    }
    _colorTheme = AppColorTheme.values.firstWhere(
      (item) => item.key == saved,
      orElse: () => AppColorTheme.standard,
    );
  }

  Future<void> select(AppColorTheme value) async {
    if (_colorTheme == value) return;
    _colorTheme = value;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_preferenceKey, value.key);
  }

  Future<void> setThemeMode(AppThemeMode value) async {
    if (_selectedThemeMode == value) return;
    _selectedThemeMode = value;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_themeModePreferenceKey, value.key);
  }
}

final ThemeController themeController = ThemeController();
