import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';

import '../auth/user_session.dart';
import '../crypto/crypto_service.dart';
import '../crypto/key_vault.dart';
import '../data/health_repository.dart';
import '../membership/membership_service.dart';
import '../network/ai_api.dart';
import '../network/api_client.dart';
import '../network/auth_api.dart';
import '../notification/reminder_scheduler.dart';
import '../storage/app_database.dart';
import '../sync/sync_service.dart';

final GetIt sl = GetIt.instance;

Future<void> setupServiceLocator() async {
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

  final healthRepository = HealthRepository(database: appDatabase);
  await healthRepository.initialize();
  sl.registerSingleton<HealthRepository>(healthRepository);

  final scheduler = ReminderScheduler(repository: healthRepository);
  sl.registerSingleton<ReminderScheduler>(scheduler);

  final apiClient = ApiClient();
  sl.registerSingleton<ApiClient>(apiClient);

  // 启动时若已有 Token，立即注入 ApiClient，让后续 API 调用都带上认证
  if (UserSession.instance.isAccountLogin) {
    apiClient.setAccessToken(UserSession.instance.accessToken);
  }

  sl.registerSingleton<AuthApi>(AuthApi(client: apiClient));

  sl.registerSingleton<SyncService>(SyncService(
    apiClient: apiClient,
    cryptoService: sl<CryptoService>(),
    database: appDatabase,
    repository: healthRepository,
  ));

  sl.registerLazySingleton<MembershipService>(
    () => MembershipService(client: apiClient),
  );

  sl.registerSingleton<AiApi>(AiApi(client: apiClient));
}
