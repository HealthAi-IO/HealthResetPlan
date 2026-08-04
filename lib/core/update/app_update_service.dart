import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../network/api_client.dart';

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.latestVersion,
    required this.forceUpdate,
    required this.packageUrl,
    required this.releaseNotes,
    required this.packageSha256,
    this.packageSizeMb,
  });

  final String latestVersion;
  final bool forceUpdate;
  final String packageUrl;
  final String releaseNotes;
  final String packageSha256;
  final num? packageSizeMb;

  static AppUpdateInfo? fromJson(Map<String, dynamic> json) {
    if (json['hasUpdate'] != true) return null;

    final latestVersion = json['latestVersion'] as String? ?? '';
    final packageUrl = json['packageUrl'] as String? ?? '';
    final packageSha256 = json['packageSha256'] as String? ?? '';
    if (latestVersion.isEmpty || !isTrustedPackageUrl(packageUrl)) return null;
    if (packageSha256.isNotEmpty &&
        !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(packageSha256)) {
      return null;
    }

    return AppUpdateInfo(
      latestVersion: latestVersion,
      forceUpdate: json['forceUpdate'] == true,
      packageUrl: packageUrl,
      releaseNotes: json['releaseNotes'] as String? ?? '',
      packageSha256: packageSha256.toLowerCase(),
      packageSizeMb: json['packageSizeMb'] as num?,
    );
  }
}

bool isTrustedPackageUrl(String value) {
  final uri = Uri.tryParse(value);
  return uri != null &&
      uri.scheme == 'https' &&
      uri.host == 'jkcqplan.com' &&
      !uri.hasPort &&
      uri.userInfo.isEmpty &&
      uri.path.startsWith('/downloads/');
}

class AppUpdateService {
  const AppUpdateService({required ApiClient client}) : _client = client;

  final ApiClient _client;

  Future<AppUpdateInfo?> check() async {
    final platform = _supportedPlatform();
    if (platform == null) return null;

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final prefs = await SharedPreferences.getInstance();
      final response = await _client.dio.get<dynamic>(
        '/releases/check',
        queryParameters: {
          'platform': platform,
          'currentVersion': packageInfo.version,
          'channel': appReleaseChannel,
          'deviceId': prefs.getString('client_device_id') ?? '',
        },
      );
      final body = response.data;
      if (body is! Map || body['code'] != 0 || body['data'] is! Map) {
        return null;
      }
      return AppUpdateInfo.fromJson(
        Map<String, dynamic>.from(body['data'] as Map),
      );
    } catch (_) {
      return null;
    }
  }

  String? _supportedPlatform() {
    if (kIsWeb) return null;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.windows => 'windows',
      _ => null,
    };
  }
}
