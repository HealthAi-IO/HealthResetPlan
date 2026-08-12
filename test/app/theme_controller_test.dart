import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_reset_plan/app/app_theme.dart';
import 'package:health_reset_plan/app/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('新用户默认跟随系统', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = ThemeController();

    await controller.load();

    expect(controller.selectedThemeMode, AppThemeMode.system);
    expect(controller.themeMode, ThemeMode.system);
  });

  test('主题颜色和显示模式会持久化', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = ThemeController();

    await controller.select(AppColorTheme.emerald);
    await controller.setThemeMode(AppThemeMode.dark);

    final restored = ThemeController();
    await restored.load();
    expect(restored.colorTheme, AppColorTheme.emerald);
    expect(restored.selectedThemeMode, AppThemeMode.dark);
    expect(restored.themeMode, ThemeMode.dark);
  });

  test('三种显示模式映射到对应的 Flutter 主题模式', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = ThemeController();

    for (final mode in AppThemeMode.values) {
      await controller.setThemeMode(mode);
      expect(controller.themeMode, mode.themeMode);
    }
  });

  test('旧深色配置迁移为深色模式', () async {
    SharedPreferences.setMockInitialValues({'app_dark_mode_v1': true});
    final controller = ThemeController();

    await controller.load();

    expect(controller.selectedThemeMode, AppThemeMode.dark);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('app_theme_mode_v1'), 'dark');
  });

  test('旧浅色配置迁移为浅色模式', () async {
    SharedPreferences.setMockInitialValues({'app_dark_mode_v1': false});
    final controller = ThemeController();

    await controller.load();

    expect(controller.selectedThemeMode, AppThemeMode.light);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('app_theme_mode_v1'), 'light');
  });

  test('全局兼容色会跟随主题和深浅模式变化', () async {
    SharedPreferences.setMockInitialValues({});
    await themeController.setThemeMode(AppThemeMode.light);
    await themeController.select(AppColorTheme.ocean);
    final oceanPrimary = AppTheme.primaryBlue;
    final lightSurface = AppTheme.surface;

    await themeController.select(AppColorTheme.emerald);
    expect(AppTheme.primaryBlue, isNot(oceanPrimary));

    await themeController.setThemeMode(AppThemeMode.dark);
    expect(AppTheme.surface, isNot(lightSurface));
  });
}
