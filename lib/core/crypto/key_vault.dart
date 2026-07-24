import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:bip39/bip39.dart' as bip39;
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 用户主密钥（UMK）安全存储。
///
/// - macOS / iOS：Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`)
/// - Android：Keystore（StrongBox 优先）+ EncryptedSharedPreferences
/// - Windows：Credential Manager
/// - Web：基于 IndexedDB + WebCrypto（[flutter_secure_storage] Web 实现）
///
/// 注意：UMK 仅存在于用户设备，**绝不上传服务端**。
class KeyVault {
  KeyVault({required this.storage});

  final FlutterSecureStorage storage;

  static const _umkKey = 'hrp_umk_v1';
  static const _backedUpKey = 'hrp_umk_backed_up';
  static const _ownerKey = 'hrp_umk_owner_v1';

  Future<KeyVaultState> status() async {
    try {
      final encoded = await storage.read(key: _umkKey);
      if (encoded == null || encoded.isEmpty) return KeyVaultState.missing;
      final decoded = base64Decode(encoded);
      if (decoded.length != 32) return KeyVaultState.unreadable;
      return await isBackedUp()
          ? KeyVaultState.ready
          : KeyVaultState.unconfirmed;
    } catch (_) {
      return KeyVaultState.unreadable;
    }
  }

  /// 将设备上的 UMK 绑定到账号。首次绑定沿用已有本地密钥；切换账号时销毁旧账号密钥。
  Future<bool> bindToAccount(String userId) async {
    final owner = await storage.read(key: _ownerKey);
    if (owner == null || owner.isEmpty) {
      await storage.write(key: _ownerKey, value: userId);
      return false;
    }
    if (owner == userId) return false;
    await destroy();
    await storage.write(key: _ownerKey, value: userId);
    return true;
  }

  /// 读取 UMK；未生成或未恢复时返回 null。
  Future<Uint8List?> readUmk() async {
    final encoded = await storage.read(key: _umkKey);
    if (encoded == null || encoded.isEmpty) return null;
    try {
      final decoded = Uint8List.fromList(base64Decode(encoded));
      return decoded.length == 32 ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  /// 生成新的 UMK（32 字节 / 256 bit）并写入安全存储。
  ///
  /// 一定要在 [generate] 之后引导用户完成备份，再调用 [markBackedUp]。
  Future<Uint8List> generate() async {
    final rand = Random.secure();
    final bytes = Uint8List(32);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = rand.nextInt(256);
    }
    await _writeAndVerify(bytes, backedUp: false);
    return bytes;
  }

  /// 从用户输入的 BIP39 助记词恢复 UMK 并写入安全存储。
  Future<Uint8List> restoreFromMnemonic(String mnemonic) async {
    final normalized = mnemonic.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (!bip39.validateMnemonic(normalized)) {
      throw const KeyVaultException('助记词不匹配，请核对');
    }
    final entropyHex = bip39.mnemonicToEntropy(normalized);
    final umk = Uint8List.fromList(
      List<int>.generate(
        entropyHex.length ~/ 2,
        (index) => int.parse(
          entropyHex.substring(index * 2, index * 2 + 2),
          radix: 16,
        ),
      ),
    );
    if (umk.length != 32) {
      throw const KeyVaultException('助记词不匹配，请核对');
    }
    await _writeAndVerify(umk, backedUp: true);
    return umk;
  }

  /// 将 UMK 编码为 BIP39 助记词供用户备份（默认 24 词）。
  String exportMnemonic(Uint8List umk) {
    if (umk.length != 32) {
      throw ArgumentError('UMK 长度必须是 32 字节');
    }
    return bip39.entropyToMnemonic(_bytesToHex(umk));
  }

  Future<void> markBackedUp() =>
      storage.write(key: _backedUpKey, value: 'true');

  Future<bool> isBackedUp() async {
    final v = await storage.read(key: _backedUpKey);
    return v == 'true';
  }

  /// 公开密钥指纹，仅用于服务端判断同一把 UMK 是否仍在使用。
  ///
  /// 指纹是 SHA-256(固定前缀 + UMK) 的摘要，不能用于解密数据。
  Future<String?> publicFingerprint() async {
    final umk = await readUmk();
    if (umk == null) return null;
    final hash = await Sha256().hash([
      ...utf8.encode('hrp-umk-public-fingerprint:v1:'),
      ...umk,
    ]);
    return _bytesToHex(Uint8List.fromList(hash.bytes));
  }

  /// Validates a mnemonic and derives its public fingerprint without writing it.
  Future<String> fingerprintFromMnemonic(String mnemonic) async {
    final normalized =
        mnemonic.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    if (!bip39.validateMnemonic(normalized)) {
      throw KeyVaultException('助记词无效，请核对 24 个单词');
    }
    final entropy = bip39.mnemonicToEntropy(normalized);
    final umk = Uint8List.fromList(List<int>.generate(
      entropy.length ~/ 2,
      (index) =>
          int.parse(entropy.substring(index * 2, index * 2 + 2), radix: 16),
    ));
    final hash = await Sha256().hash([
      ...utf8.encode('hrp-umk-public-fingerprint:v1:'),
      ...umk,
    ]);
    return _bytesToHex(Uint8List.fromList(hash.bytes));
  }

  // ── 文件加密密钥派生（HKDF） ──────────────────────────────────

  /// 从 UMK 派生文件加密密钥 K_file（HKDF-SHA256，info="file.v1"）。
  ///
  /// 用于包裹 DEK：K_file 不直接加密数据，只用来加密（Wrap）随机生成的 DEK。
  /// 这样每个文件都有独立 DEK，K_file 泄露也只影响已知密文的解密能力。
  Future<Uint8List> deriveFileKey() async {
    final umk = await readUmk();
    if (umk == null) throw StateError('UMK 未生成，请先开通云同步并完成密钥备份');
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final derived = await hkdf.deriveKey(
      secretKey: SecretKey(umk),
      nonce: const [],
      info: utf8.encode('file.v1'),
    );
    return Uint8List.fromList(await derived.extractBytes());
  }

  // ── DEK 工具方法 ──────────────────────────────────────────────

  /// 生成 32 字节随机 DEK（每个文件独立生成）。
  static Uint8List generateDek() {
    final rand = Random.secure();
    final dek = Uint8List(32);
    for (var i = 0; i < 32; i++) {
      dek[i] = rand.nextInt(256);
    }
    return dek;
  }

  /// 用 K_file 包裹（加密）DEK，返回 `{wrappedDek, iv, tag}` Base64 三元组。
  ///
  /// 使用 AES-256-GCM：IV 12 字节随机，Tag 16 字节，AAD 为空。
  static Future<Map<String, String>> wrapDek(
    Uint8List dek,
    Uint8List kFile,
  ) async {
    final algorithm = AesGcm.with256bits();
    final nonce = algorithm.newNonce();
    final box = await algorithm.encrypt(
      dek,
      secretKey: SecretKey(kFile),
      nonce: nonce,
    );
    return {
      'wrappedDek': base64Encode(box.cipherText),
      'iv': base64Encode(nonce),
      'tag': base64Encode(box.mac.bytes),
    };
  }

  /// 用 DEK 加密任意字节数组，返回 `{cipher, iv, tag}` Base64 三元组。
  static Future<Map<String, String>> encryptWithDek(
    Uint8List plaintext,
    Uint8List dek,
  ) async {
    final algorithm = AesGcm.with256bits();
    final nonce = algorithm.newNonce();
    final box = await algorithm.encrypt(
      plaintext,
      secretKey: SecretKey(dek),
      nonce: nonce,
    );
    return {
      'cipher': base64Encode(box.cipherText),
      'iv': base64Encode(nonce),
      'tag': base64Encode(box.mac.bytes),
    };
  }

  /// 销毁本设备上的 UMK（用户退出登录 / 注销账号时调用）。
  Future<void> destroy() async {
    await storage.delete(key: _umkKey);
    await storage.delete(key: _backedUpKey);
    await storage.delete(key: _ownerKey);
  }

  Future<void> _writeAndVerify(
    Uint8List umk, {
    required bool backedUp,
  }) async {
    try {
      await storage.write(key: _umkKey, value: base64Encode(umk));
      await storage.write(
          key: _backedUpKey, value: backedUp ? 'true' : 'false');
      final saved = await readUmk();
      if (saved == null || !_bytesEqual(saved, umk)) {
        throw const KeyVaultException('本地存储异常，无法恢复密钥');
      }
    } on KeyVaultException {
      rethrow;
    } catch (_) {
      throw const KeyVaultException('本地存储异常，无法恢复密钥');
    }
  }

  bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  String _bytesToHex(Uint8List bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }
}

enum KeyVaultState {
  missing,
  unconfirmed,
  unreadable,
  ready;

  String get syncMessage => switch (this) {
        KeyVaultState.missing => '尚未生成主密钥（UMK），请先生成并确认备份助记词。',
        KeyVaultState.unconfirmed => '主密钥尚未确认备份，请确认已离线保存助记词后再开启云同步。',
        KeyVaultState.unreadable => '本地安全存储不可读取，请使用原 24 词助记词恢复主密钥。',
        KeyVaultState.ready => '',
      };
}

class KeyVaultException implements Exception {
  const KeyVaultException(this.message);

  final String message;

  @override
  String toString() => message;
}
