import 'package:flutter_test/flutter_test.dart';
import 'package:health_reset_plan/app/app_settings_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('饮水目标默认不设置，长辈打卡语音默认关闭', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = AppSettingsController();
    await controller.load();
    expect(controller.waterGoalMl, isNull);
    expect(controller.seniorClockVoice, isFalse);
  });

  test('饮水目标和长辈语音设置可以持久化与关闭', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = AppSettingsController();
    await controller.load();
    await controller.setWaterGoalMl(1800);
    await controller.setSeniorClockVoice(true);

    final restored = AppSettingsController();
    await restored.load();
    expect(restored.waterGoalMl, 1800);
    expect(restored.seniorClockVoice, isTrue);

    await restored.setWaterGoalMl(null);
    expect(restored.waterGoalMl, isNull);
  });
}
