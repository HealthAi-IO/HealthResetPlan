import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:bip39/bip39.dart' as bip39;
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

  /// 读取 UMK；未生成或未恢复时返回 null。
  Future<Uint8List?> readUmk() async {
    final encoded = await storage.read(key: _umkKey);
    if (encoded == null || encoded.isEmpty) return null;
    return Uint8List.fromList(base64Decode(encoded));
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
    await storage.write(key: _umkKey, value: base64Encode(bytes));
    await storage.write(key: _backedUpKey, value: 'false');
    return bytes;
  }

  /// 从用户输入的 BIP39 助记词恢复 UMK 并写入安全存储。
  Future<Uint8List> restoreFromMnemonic(String mnemonic) async {
    final normalized = mnemonic.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (!bip39.validateMnemonic(normalized)) {
      throw ArgumentError('助记词无效，请检查后重新输入');
    }
    final entropyHex = bip39.mnemonicToEntropy(normalized);
    final umk = Uint8List.fromList(
      List<int>.generate(
        entropyHex.length ~/ 2,
        (index) => int.parse(entropyHex.substring(index * 2, index * 2 + 2), radix: 16),
      ),
    );
    await storage.write(key: _umkKey, value: base64Encode(umk));
    await storage.write(key: _backedUpKey, value: 'true');
    return umk;
  }

  /// 将 UMK 编码为 BIP39 助记词供用户备份（默认 24 词）。
  String exportMnemonic(Uint8List umk) {
    if (umk.length != 32) {
      throw ArgumentError('UMK 长度必须是 32 字节');
    }
    return bip39.entropyToMnemonic(_bytesToHex(umk));
  }

  Future<void> markBackedUp() => storage.write(key: _backedUpKey, value: 'true');

  Future<bool> isBackedUp() async {
    final v = await storage.read(key: _backedUpKey);
    return v == 'true';
  }

  /// 销毁本设备上的 UMK（用户退出登录 / 注销账号时调用）。
  Future<void> destroy() async {
    await storage.delete(key: _umkKey);
    await storage.delete(key: _backedUpKey);
  }

  String _bytesToHex(Uint8List bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }
}
