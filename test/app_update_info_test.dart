import 'package:flutter_test/flutter_test.dart';
import 'package:health_reset_plan/core/update/app_update_service.dart';

void main() {
  test('returns update details when a new version is available', () {
    final update = AppUpdateInfo.fromJson({
      'hasUpdate': true,
      'forceUpdate': true,
      'latestVersion': '1.1.0',
      'packageUrl': 'https://example.com/app.exe',
      'packageSizeMb': 20.3,
      'releaseNotes': '新增版本更新提醒',
    });

    expect(update?.latestVersion, '1.1.0');
    expect(update?.forceUpdate, isTrue);
    expect(update?.packageSizeMb, 20.3);
  });

  test('returns no update when server reports the current version is latest',
      () {
    final update = AppUpdateInfo.fromJson({
      'hasUpdate': false,
      'latestVersion': '1.0.10',
      'packageUrl': 'https://example.com/app.exe',
    });

    expect(update, isNull);
  });
}
