import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_reset_plan/core/crypto/crypto_service.dart';
import 'package:health_reset_plan/core/crypto/key_vault.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('AES-GCM authenticates sync record AAD', () async {
    const storage = FlutterSecureStorage();
    final vault = KeyVault(storage: storage);
    await vault.generate();
    final crypto = AesGcmCryptoService(keyVault: vault);
    final aad = utf8.encode('hrp-sync:v2:user:plan:record:1');
    final encrypted =
        await crypto.encryptString('private health data', aad: aad);

    expect(await crypto.decryptToString(encrypted, aad: aad),
        'private health data');
    expect(
      () => crypto.decryptToString(
        encrypted,
        aad: utf8.encode('hrp-sync:v2:user:plan:other-record:1'),
      ),
      throwsA(anything),
    );
  });

  test('switching accounts destroys the previous account UMK', () async {
    const storage = FlutterSecureStorage();
    final vault = KeyVault(storage: storage);
    await vault.generate();

    expect(await vault.bindToAccount('account-a'), isFalse);
    expect(await vault.readUmk(), isNotNull);
    expect(await vault.bindToAccount('account-b'), isTrue);
    expect(await vault.readUmk(), isNull);
  });
}
