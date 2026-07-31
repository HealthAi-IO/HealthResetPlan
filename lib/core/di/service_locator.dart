import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../ai/ai_plan_generation_controller.dart';
import '../auth/user_session.dart';
import '../data/chat_repository.dart';
import '../data/health_repository.dart';
import '../data/online_data_service.dart';
import '../membership/membership_service.dart';
import '../network/ai_api.dart';
import '../network/ai_consent_api.dart';
import '../network/api_client.dart';
import '../network/auth_api.dart';
import '../network/file_api.dart';
import '../network/online_data_api.dart';
import '../network/telemetry_api.dart';
import '../notification/reminder_scheduler.dart';
import '../storage/app_database.dart';

final GetIt sl = GetIt.instance;

/// 服务定位器初始化。
///
/// 启动加速策略：
/// 1. 同步注册不依赖 IO 的轻量级单例
/// 2. 恢复登录会话并初始化在线数据内存缓存。
/// 3. 其余 API/Service 立即注册（构造函数都不阻塞）。
Future<void> setupServiceLocator() async {
  // ── 同步注册（瞬时） ─────────────────────────────────────────
  sl.registerLazySingleton<Logger>(() => Logger());

  final appDatabase = AppDatabase.instance;
  sl.registerSingleton<AppDatabase>(appDatabase);

  // 先恢复账号，再加载对应的在线数据。
  final healthRepository = HealthRepository(database: appDatabase);
  await UserSession.instance.load();
  await appDatabase.open();
  final startupUserId = UserSession.instance.userId;
  final prefs = await SharedPreferences.getInstance();
  final startupSpace = startupUserId ?? 'signed-out';
  await appDatabase.switchSpace(startupSpace);
  await healthRepository.initialize();
  sl.registerSingleton<HealthRepository>(healthRepository);

  // 仓库类 - 仅持有数据库引用，构造瞬时
  sl.registerSingleton<ChatRepository>(ChatRepository(database: appDatabase));

  // ── 网络相关 ─────────────────────────────────────────────────
  final apiClient = ApiClient();
  final packageInfo = await PackageInfo.fromPlatform();
  var deviceId = prefs.getString('client_device_id');
  if (deviceId == null || deviceId.isEmpty) {
    deviceId = const Uuid().v4();
    await prefs.setString('client_device_id', deviceId);
  }
  apiClient.setDeviceHeaders(
    deviceId: deviceId,
    platform: _platformName(),
    appVersion: packageInfo.version,
  );
  sl.registerSingleton<ApiClient>(apiClient);

  // 启动时若已有 Token，立即注入 ApiClient，让后续 API 调用都带上认证
  if (UserSession.instance.isAccountLogin) {
    apiClient.setAccessToken(UserSession.instance.accessToken);
  }

  sl.registerSingleton<AuthApi>(AuthApi(client: apiClient));
  sl.registerSingleton<FileApi>(FileApi(client: apiClient));
  sl.registerSingleton<TelemetryApi>(
    TelemetryApi(
      client: apiClient,
      platform: _platformName(),
      appVersion: packageInfo.version,
    ),
  );

  final onlineDataApi = OnlineDataApi(client: apiClient);
  sl.registerSingleton<OnlineDataApi>(onlineDataApi);
  final onlineDataService = OnlineDataService(
    database: appDatabase,
    api: onlineDataApi,
    repository: healthRepository,
  );
  apiClient.setSessionExpiredHandler(() async {
    await onlineDataService.signOut();
    await UserSession.instance.signOut(sessionExpired: true);
  });
  sl.registerSingleton<OnlineDataService>(onlineDataService);
  if (startupUserId != null) {
    unawaited(_bindStartupData(onlineDataService, startupUserId));
  }

  // 延迟创建：在线能力与通知调度首次访问时才实例化
  sl.registerLazySingleton<MembershipService>(
    () => MembershipService(client: apiClient),
  );
  sl.registerLazySingleton<AiApi>(() => AiApi(client: apiClient));
  sl.registerLazySingleton<AiPlanGenerationController>(
    () => AiPlanGenerationController(
      repository: healthRepository,
      aiApi: sl<AiApi>(),
    ),
  );
  sl.registerLazySingleton<AiConsentApi>(() => AiConsentApi(client: apiClient));

  // 通知调度也改为延迟（main.dart 后台再触发 initialize）
  sl.registerLazySingleton<ReminderScheduler>(
    () => ReminderScheduler(repository: healthRepository),
  );
}

Future<void> _bindStartupData(
  OnlineDataService onlineDataService,
  String userId,
) async {
  try {
    await onlineDataService.bindToAccount(userId);
  } on DioException catch (error, stackTrace) {
    if (error.response?.statusCode == 401 &&
        !UserSession.instance.isAccountLogin) {
      return;
    }
    sl<Logger>().e('加载线上数据失败', error: error, stackTrace: stackTrace);
  } catch (error, stackTrace) {
    sl<Logger>().e('加载线上数据失败', error: error, stackTrace: stackTrace);
  }
}

String _platformName() {
  if (kIsWeb) return 'web';
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => 'android',
    TargetPlatform.iOS => 'ios',
    TargetPlatform.windows => 'windows',
    TargetPlatform.macOS => 'macos',
    TargetPlatform.linux => 'linux',
    TargetPlatform.fuchsia => 'fuchsia',
  };
}
