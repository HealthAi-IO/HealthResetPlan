import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';

import '../crypto/crypto_service.dart';
import '../crypto/key_vault.dart';
import '../storage/app_database.dart';

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

  sl.registerSingleton<AppDatabase>(AppDatabase.instance);
}
