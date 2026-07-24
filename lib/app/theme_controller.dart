import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppColorTheme {
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

  AppColorTheme _colorTheme = AppColorTheme.ocean;

  AppColorTheme get colorTheme => _colorTheme;

  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    final saved = preferences.getString(_preferenceKey);
    _colorTheme = AppColorTheme.values.firstWhere(
      (item) => item.key == saved,
      orElse: () => AppColorTheme.ocean,
    );
  }

  Future<void> select(AppColorTheme value) async {
    if (_colorTheme == value) return;
    _colorTheme = value;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_preferenceKey, value.key);
  }
}

final ThemeController themeController = ThemeController();
