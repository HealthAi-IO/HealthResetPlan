import 'package:flutter_test/flutter_test.dart';
import 'package:health_reset_plan/app/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('selected color theme is restored on the next launch', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = ThemeController();

    await controller.load();
    expect(controller.colorTheme, AppColorTheme.standard);

    await controller.select(AppColorTheme.emerald);
    final restored = ThemeController();
    await restored.load();

    expect(restored.colorTheme, AppColorTheme.emerald);
  });

  test('existing ocean preference remains unchanged', () async {
    SharedPreferences.setMockInitialValues({
      'app_color_theme_v1': 'ocean',
    });
    final controller = ThemeController();

    await controller.load();

    expect(controller.colorTheme, AppColorTheme.ocean);
  });
}
