import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../auth/user_session.dart';
import '../crypto/crypto_service.dart';
import '../crypto/key_vault.dart';
import '../data/chat_repository.dart';
import '../data/health_repository.dart';
import '../membership/alipay_pay_service.dart';
import '../membership/membership_service.dart';
import '../membership/wechat_pay_service.dart';
import '../network/ai_api.dart';
import '../network/api_client.dart';
import '../network/auth_api.dart';
import '../notification/reminder_scheduler.dart';
import '../storage/app_database.dart';
import '../sync/sync_service.dart';

final GetIt sl = GetIt.instance;

/// 服务定位器初始化。
///
/// 启动加速策略：
/// 1. 同步注册不依赖 IO 的轻量级单例（Logger / SecureStorage / KeyVault 等）
/// 2. **并行执行**两个最耗时的步骤：
///    - SharedPreferences 初始化（UserSession.load）
///    - 数据库打开/迁移（HealthRepository.initialize）
/// 3. 其余 API/Service 立即注册（构造函数都不阻塞）
Future<void> setupServiceLocator() async {
  // ── 同步注册（瞬时） ─────────────────────────────────────────
  sl.registerLazySingleton<Logger>(() => Logger());

  const secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.unlocked_this_device,
    ),
    mOptions: MacOsOptions(
      accessibility: KeychainAccessibility.unlocked_this_device,
    ),
  );
  sl.registerSingleton<FlutterSecureStorage>(secureStorage);

  final keyVault = KeyVault(storage: secureStorage);
  sl.registerSingleton<KeyVault>(keyVault);

  sl.registerLazySingleton<CryptoService>(
    () => AesGcmCryptoService(keyVault: keyVault),
  );

  final appDatabase = AppDatabase.instance;
  sl.registerSingleton<AppDatabase>(appDatabase);

  // ── 并行执行 IO 密集的初始化 ────────────────────────────────
  // 1. UserSession 从 SharedPreferences/SecureStorage 加载
  // 2. HealthRepository 打开数据库
  final healthRepository = HealthRepository(database: appDatabase);
  await Future.wait([
    UserSession.instance.load(),
    healthRepository.initialize(),
  ]);
  sl.registerSingleton<HealthRepository>(healthRepository);

  // 仓库类 - 仅持有数据库引用，构造瞬时
  sl.registerSingleton<ChatRepository>(ChatRepository(database: appDatabase));

  // ── 网络相关 ─────────────────────────────────────────────────
  final apiClient = ApiClient();
  final prefs = await SharedPreferences.getInstance();
  var deviceId = prefs.getString('client_device_id');
  if (deviceId == null || deviceId.isEmpty) {
    deviceId = const Uuid().v4();
    await prefs.setString('client_device_id', deviceId);
  }
  apiClient.setDeviceHeaders(
    deviceId: deviceId,
    platform: _platformName(),
    appVersion: '0.1.0',
  );
  sl.registerSingleton<ApiClient>(apiClient);

  // 启动时若已有 Token，立即注入 ApiClient，让后续 API 调用都带上认证
  if (UserSession.instance.isAccountLogin) {
    apiClient.setAccessToken(UserSession.instance.accessToken);
  }

  sl.registerSingleton<AuthApi>(AuthApi(client: apiClient));

  sl.registerSingleton<SyncService>(SyncService(
    apiClient: apiClient,
    cryptoService: sl<CryptoService>(),
    keyVault: keyVault,
    database: appDatabase,
    repository: healthRepository,
  ));

  // 延迟创建：会员/AI/通知调度首次访问时才实例化
  sl.registerLazySingleton<MembershipService>(
    () => MembershipService(client: apiClient),
  );
  sl.registerLazySingleton<AlipayPayService>(() => AlipayPayService());
  sl.registerLazySingleton<WechatPayService>(() => WechatPayService());
  sl.registerLazySingleton<AiApi>(() => AiApi(client: apiClient));

  // 通知调度也改为延迟（main.dart 后台再触发 initialize）
  sl.registerLazySingleton<ReminderScheduler>(
    () => ReminderScheduler(repository: healthRepository),
  );
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
