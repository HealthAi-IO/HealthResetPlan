import 'package:flutter_test/flutter_test.dart';
import 'package:health_reset_plan/core/update/app_update_service.dart';

void main() {
  test('returns update details when a new version is available', () {
    const sha256 =
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    final update = AppUpdateInfo.fromJson({
      'hasUpdate': true,
      'forceUpdate': true,
      'latestVersion': '1.1.0',
      'packageUrl': 'https://jkcqplan.com/downloads/android/app.apk',
      'packageSha256': sha256,
      'packageSizeMb': 20.3,
      'releaseNotes': '新增版本更新提醒',
    });

    expect(update?.latestVersion, '1.1.0');
    expect(update?.forceUpdate, isTrue);
    expect(update?.packageSizeMb, 20.3);
    expect(update?.packageSha256, sha256);
  });

  test('returns no update when server reports the current version is latest',
      () {
    final update = AppUpdateInfo.fromJson({
      'hasUpdate': false,
      'latestVersion': '1.0.10',
      'packageUrl': 'https://jkcqplan.com/downloads/android/app.apk',
    });

    expect(update, isNull);
  });

  test('rejects update URLs outside the official HTTPS download path', () {
    for (final packageUrl in [
      'http://jkcqplan.com/downloads/android/app.apk',
      'https://jkcqplan.com.evil.example/downloads/android/app.apk',
      'https://jkcqplan.com/other/app.apk',
    ]) {
      expect(
        AppUpdateInfo.fromJson({
          'hasUpdate': true,
          'latestVersion': '1.1.0',
          'packageUrl': packageUrl,
        }),
        isNull,
      );
    }
  });

  test('rejects malformed package hashes', () {
    final update = AppUpdateInfo.fromJson({
      'hasUpdate': true,
      'latestVersion': '1.1.0',
      'packageUrl': 'https://jkcqplan.com/downloads/android/app.apk',
      'packageSha256': 'not-a-sha256',
    });

    expect(update, isNull);
  });
}
