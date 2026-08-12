import 'dart:async';

import 'package:dio/dio.dart';

import 'api_client.dart';
import 'api_response.dart';

/// 认证 API：手机号注册 / 登录 / 刷新 Token / 注销。
class AuthApi {
  AuthApi({required ApiClient client}) : _client = client;
  final ApiClient _client;

  Future<AuthResult> registerPhone({
    required String phone,
    required String registrationTicket,
    String? password,
    required String nickname,
    required String agreementVersion,
  }) async {
    final resp = await _client.dio.post('/auth/sms/register', data: {
      'phone': phone,
      'registrationTicket': registrationTicket,
      if (password != null && password.isNotEmpty) 'password': password,
      'nickname': nickname,
      'agreedToTerms': true,
      'agreementVersion': agreementVersion,
    });
    return AuthResult.fromJson(_unwrapData(resp.data));
  }

  Future<PhoneVerificationResult> verifyPhone({
    required String phone,
    required String code,
  }) async {
    final resp = await _client.dio.post('/auth/sms/verify', data: {
      'phone': phone,
      'code': code,
    });
    return PhoneVerificationResult.fromJson(_unwrapData(resp.data));
  }

  Future<AuthResult> loginWithPhonePassword({
    required String phone,
    required String password,
    required String captchaTicket,
  }) async {
    final resp = await _client.dio.post('/auth/login', data: {
      'phone': phone,
      'password': password,
      'captchaTicket': captchaTicket,
    });
    return AuthResult.fromJson(_unwrapData(resp.data));
  }

  Future<CaptchaChallenge> createLoginCaptcha({
    required String phone,
  }) async {
    final resp = await _client.dio.post('/auth/captcha/create', data: {
      'scene': 'login',
      'principal': phone,
    });
    return CaptchaChallenge.fromJson(_unwrapData(resp.data));
  }

  Future<String> verifyLoginCaptcha({
    required String captchaId,
    required String phone,
    required double finalX,
    required List<CaptchaTrajectoryPoint> trajectory,
  }) async {
    final resp = await _client.dio.post('/auth/captcha/verify', data: {
      'captchaId': captchaId,
      'scene': 'login',
      'principal': phone,
      'finalX': finalX,
      'trajectory': trajectory.map((point) => point.toJson()).toList(),
    });
    final data = _unwrapData(resp.data);
    return data['ticket'] as String? ?? '';
  }

  Future<PasswordResetCodeResult> sendSmsLoginCode({
    required String phone,
    required String captchaTicket,
  }) async {
    final resp = await _client.dio.post('/auth/sms/send-code', data: {
      'phone': phone,
      'captchaTicket': captchaTicket,
    });
    return PasswordResetCodeResult.fromJson(_unwrapData(resp.data));
  }

  /// 刷新 Access Token
  Future<AuthResult> refresh(String refreshToken) async {
    final resp = await _client.dio.post('/auth/refresh', data: {
      'refreshToken': refreshToken,
    });
    return AuthResult.fromJson(_unwrapData(resp.data));
  }

  /// 注销（删除服务端 session）
  Future<void> logout(String refreshToken) async {
    try {
      await _client.dio.post('/auth/logout', data: {
        'refreshToken': refreshToken,
      });
    } catch (_) {
      // 注销失败不阻断本地清理
    }
  }

  Future<void> setInitialPassword(String password) async {
    await _client.dio.post('/auth/password/set', data: {'password': password});
  }

  /// 注销账号：服务端停用账号，并让该账号云端密文进入 30 天保留期。
  Future<PasswordResetCodeResult> sendCancelAccountCode(String phone) async {
    final resp = await _client.dio
        .post('/auth/cancel-account/send-code', data: {'phone': phone});
    return PasswordResetCodeResult.fromJson(_unwrapData(resp.data));
  }

  Future<void> cancelAccount({
    required String phone,
    required String code,
  }) async {
    await _client.dio.post('/auth/cancel-account', data: {
      'phone': phone,
      'code': code,
    });
  }

  Future<PasswordResetCodeResult> sendAccountRecoveryCode(String phone) async {
    final resp = await _client.dio
        .post('/auth/account-recovery/send-code', data: {'phone': phone});
    return PasswordResetCodeResult.fromJson(_unwrapData(resp.data));
  }

  Future<AuthResult> reactivateAccount({
    required String phone,
    required String code,
  }) async {
    final resp =
        await _client.dio.post('/auth/account-recovery/reactivate', data: {
      'phone': phone,
      'code': code,
    });
    return AuthResult.fromJson(_unwrapData(resp.data));
  }

  Future<PasswordResetCodeResult> sendPasswordResetCode({
    required String credType,
    required String identifier,
  }) async {
    final resp =
        await _client.dio.post('/auth/password-reset/send-code', data: {
      'credType': credType,
      'identifier': identifier,
    });
    return PasswordResetCodeResult.fromJson(_unwrapData(resp.data));
  }

  Future<void> resetPassword({
    required String credType,
    required String identifier,
    required String code,
    required String newPassword,
  }) async {
    await _client.dio.post('/auth/password-reset/reset', data: {
      'credType': credType,
      'identifier': identifier,
      'code': code,
      'newPassword': newPassword,
    });
  }

  /// 获取当前登录用户的账号信息（需 JWT 认证）
  Future<AccountInfo?> fetchAccountInfo() async {
    try {
      final resp = await _client.dio.get('/users/me');
      if (resp.data is Map) {
        final data = Map<String, dynamic>.from(resp.data as Map);
        return AccountInfo(
          userId: data['userId'] as String? ?? '',
          customId: data['customId'] as String? ?? '',
          phoneTail: data['phoneTail'] as String? ?? '',
          nickname: data['nickname'] as String? ?? '',
          avatarUrl: data['avatarUrl'] as String? ?? '',
          hasCloudSync: data['hasCloudSync'] == true,
          hasPassword: data['hasPassword'] == true,
        );
      }
      return null;
    } on DioException {
      return null;
    }
  }

  Future<AccountInfo?> updateAccountProfile({
    String? nickname,
    String? avatarUrl,
  }) async {
    final data = <String, dynamic>{
      if (nickname != null && nickname.trim().isNotEmpty)
        'nickname': nickname.trim(),
      if (avatarUrl != null && avatarUrl.trim().isNotEmpty)
        'avatarUrl': avatarUrl.trim(),
    };
    if (data.isEmpty) return fetchAccountInfo();

    final resp = await _client.dio.put('/users/me', data: data);
    return AccountInfo.fromJson(requireApiMap(resp.data));
  }

  Future<String> uploadAvatar(String filePath) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath),
    });
    final resp = await _client.dio.post(
      '/files/avatar',
      data: formData,
      options: Options(contentType: 'multipart/form-data'),
    );
    final data = requireApiMap(resp.data);
    final avatarUrl = data['avatarUrl'] as String? ?? '';
    if (avatarUrl.isNotEmpty) return avatarUrl;
    throw StateError('头像上传失败');
  }

  Map<String, dynamic> _unwrapData(dynamic body) {
    if (body is! Map) {
      throw StateError('服务器响应格式异常');
    }
    return Map<String, dynamic>.from(body);
  }
}

class AuthResult {
  const AuthResult({
    required this.userId,
    required this.accessToken,
    required this.refreshToken,
    required this.accessExpiresIn,
    required this.hasPassword,
  });

  final String userId;
  final String accessToken;
  final String refreshToken;
  final int accessExpiresIn;
  final bool hasPassword;

  factory AuthResult.fromJson(Map<String, dynamic> j) => AuthResult(
        userId: j['userId'] as String,
        accessToken: j['accessToken'] as String,
        refreshToken: j['refreshToken'] as String,
        accessExpiresIn: (j['accessExpiresIn'] as num).toInt(),
        hasPassword: j['hasPassword'] == true,
      );
}

class AccountInfo {
  const AccountInfo({
    required this.userId,
    required this.customId,
    required this.phoneTail,
    required this.nickname,
    required this.avatarUrl,
    required this.hasCloudSync,
    required this.hasPassword,
  });

  final String userId;
  final String customId;
  final String phoneTail;
  final String nickname;
  final String avatarUrl;
  final bool hasCloudSync;
  final bool hasPassword;

  factory AccountInfo.fromJson(Map<String, dynamic> j) => AccountInfo(
        userId: j['userId'] as String? ?? '',
        customId: j['customId'] as String? ?? '',
        phoneTail: j['phoneTail'] as String? ?? '',
        nickname: j['nickname'] as String? ?? '',
        avatarUrl: j['avatarUrl'] as String? ?? '',
        hasCloudSync: j['hasCloudSync'] == true,
        hasPassword: j['hasPassword'] == true,
      );
}

class PasswordResetCodeResult {
  const PasswordResetCodeResult({
    required this.debugCode,
    required this.expiresIn,
  });

  final String debugCode;
  final int expiresIn;

  factory PasswordResetCodeResult.fromJson(Map<String, dynamic> j) {
    return PasswordResetCodeResult(
      debugCode: j['debugCode'] as String? ?? '',
      expiresIn: (j['expiresIn'] as num?)?.toInt() ?? 0,
    );
  }
}

class PhoneVerificationResult {
  const PhoneVerificationResult({
    required this.status,
    this.auth,
    this.registrationTicket,
  });

  final String status;
  final AuthResult? auth;
  final String? registrationTicket;

  factory PhoneVerificationResult.fromJson(Map<String, dynamic> j) {
    final token = j['token'];
    return PhoneVerificationResult(
      status: j['status'] as String? ?? '',
      auth: token is Map
          ? AuthResult.fromJson(Map<String, dynamic>.from(token))
          : null,
      registrationTicket: j['registrationTicket'] as String?,
    );
  }
}

class CaptchaChallenge {
  const CaptchaChallenge({
    required this.captchaId,
    required this.backgroundImageBase64,
    required this.pieceImageBase64,
    required this.imageWidth,
    required this.imageHeight,
    required this.pieceWidth,
  });

  final String captchaId;
  final String backgroundImageBase64;
  final String pieceImageBase64;
  final int imageWidth;
  final int imageHeight;
  final int pieceWidth;

  factory CaptchaChallenge.fromJson(Map<String, dynamic> json) {
    return CaptchaChallenge(
      captchaId: json['captchaId'] as String,
      backgroundImageBase64: json['backgroundImageBase64'] as String,
      pieceImageBase64: json['pieceImageBase64'] as String,
      imageWidth: (json['imageWidth'] as num).toInt(),
      imageHeight: (json['imageHeight'] as num).toInt(),
      pieceWidth: (json['pieceWidth'] as num).toInt(),
    );
  }
}

class CaptchaTrajectoryPoint {
  const CaptchaTrajectoryPoint({
    required this.x,
    required this.y,
    required this.t,
  });

  final double x;
  final double y;
  final int t;

  Map<String, dynamic> toJson() => {'x': x, 'y': y, 't': t};
}

/// 把 DioException 转成用户友好的错误文本
String friendlyAuthError(Object e) {
  if (e is AuthApiException) return _friendlyCaptchaError(e.message);
  if (e is DioException) {
    final data = e.response?.data;
    if (data is Map && data['message'] != null) {
      final message = data['message'].toString();
      return _friendlyCaptchaError(message);
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.connectionError) {
      return '无法连接服务器，请检查网络';
    }
    if (e.type == DioExceptionType.receiveTimeout) {
      return '服务器响应超时';
    }
    return '请求失败：${e.type.name}';
  }
  if (e is TimeoutException) return '安全验证加载超时，请点击刷新重试';
  if (e is StateError) return e.message;
  return e.toString();
}

String _friendlyCaptchaError(String message) {
  if (message.contains('trajectory') || message.contains('滑动过快')) {
    return '请对准缺口并平稳滑动后再试';
  }
  return message;
}

int? authErrorCode(Object error) {
  if (error is AuthApiException) return error.code;
  if (error is! DioException) return null;
  final data = error.response?.data;
  if (data is! Map) return null;
  return int.tryParse('${data['code'] ?? ''}');
}

class AuthApiException implements Exception {
  const AuthApiException(this.code, this.message);

  final int code;
  final String message;

  @override
  String toString() => message;
}
