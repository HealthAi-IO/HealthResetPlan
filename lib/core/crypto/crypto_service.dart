import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'key_vault.dart';

/// 端到端加密载荷。
///
/// - [cipher] 密文（AES-256-GCM）
/// - [iv] 12 字节随机 IV
/// - [tag] 16 字节 GCM Auth Tag
/// - [alg] 算法版本标识，默认 `aes-256-gcm:v1`
class EncryptedPayload {
  EncryptedPayload({
    required this.cipher,
    required this.iv,
    required this.tag,
    this.alg = 'aes-256-gcm:v1',
  });

  final Uint8List cipher;
  final Uint8List iv;
  final Uint8List tag;
  final String alg;

  Map<String, String> toJson() => {
        'cipher': base64Encode(cipher),
        'iv': base64Encode(iv),
        'tag': base64Encode(tag),
        'alg': alg,
      };

  factory EncryptedPayload.fromJson(Map<String, dynamic> json) {
    return EncryptedPayload(
      cipher: base64Decode(json['cipher'] as String),
      iv: base64Decode(json['iv'] as String),
      tag: base64Decode(json['tag'] as String),
      alg: (json['alg'] as String?) ?? 'aes-256-gcm:v1',
    );
  }
}

/// 端到端加密接口。
///
/// 所有上传到云端的敏感字段（健康指标、报告、计划、备注等）必须先经过本接口加密；
/// 服务端 **不持有** 用户主密钥（UMK），因此对密文不可见。
abstract class CryptoService {
  Future<EncryptedPayload> encrypt(Uint8List plaintext, {List<int>? aad});

  Future<Uint8List> decrypt(EncryptedPayload payload, {List<int>? aad});
}

/// 字符串便捷扩展。
extension CryptoServiceStringX on CryptoService {
  Future<EncryptedPayload> encryptString(String plaintext, {List<int>? aad}) =>
      encrypt(Uint8List.fromList(utf8.encode(plaintext)), aad: aad);

  Future<String> decryptToString(EncryptedPayload payload, {List<int>? aad}) async {
    final bytes = await decrypt(payload, aad: aad);
    return utf8.decode(bytes);
  }
}

/// AES-256-GCM 实现。
///
/// 密钥来源：[KeyVault] 持有的 UMK；调用方需要在用户已开通云同步并完成备份的前提下才会有可用的 UMK。
class AesGcmCryptoService implements CryptoService {
  AesGcmCryptoService({required this.keyVault});

  final KeyVault keyVault;
  final AesGcm _algorithm = AesGcm.with256bits();

  Future<SecretKey> _ensureKey() async {
    final key = await keyVault.readUmk();
    if (key == null) {
      throw StateError(
        '尚未生成用户主密钥（UMK），请先在「我的-云同步」中开通并完成备份。',
      );
    }
    return SecretKey(key);
  }

  @override
  Future<EncryptedPayload> encrypt(Uint8List plaintext, {List<int>? aad}) async {
    final key = await _ensureKey();
    final nonce = _algorithm.newNonce();
    final box = await _algorithm.encrypt(
      plaintext,
      secretKey: key,
      nonce: nonce,
      aad: aad ?? const <int>[],
    );
    return EncryptedPayload(
      cipher: Uint8List.fromList(box.cipherText),
      iv: Uint8List.fromList(nonce),
      tag: Uint8List.fromList(box.mac.bytes),
    );
  }

  @override
  Future<Uint8List> decrypt(EncryptedPayload payload, {List<int>? aad}) async {
    final key = await _ensureKey();
    final box = SecretBox(
      payload.cipher,
      nonce: payload.iv,
      mac: Mac(payload.tag),
    );
    final clear = await _algorithm.decrypt(
      box,
      secretKey: key,
      aad: aad ?? const <int>[],
    );
    return Uint8List.fromList(clear);
  }
}

