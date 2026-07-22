import 'package:dio/dio.dart';

import 'api_client.dart';

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
  }) async {
    final resp = await _client.dio.post('/auth/login', data: {
      'phone': phone,
      'password': password,
    });
    return AuthResult.fromJson(_unwrapData(resp.data));
  }

  Future<PasswordResetCodeResult> sendSmsLoginCode({
    required String phone,
  }) async {
    final resp = await _client.dio.post('/auth/sms/send-code', data: {
      'phone': phone,
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
  Future<void> cancelAccount() async {
    await _client.dio.post('/auth/cancel-account');
  }

  Future<PasswordResetCodeResult> sendAccountRecoveryCode(String phone) async {
    final resp = await _client.dio
        .post('/auth/account-recovery/send-code', data: {'phone': phone});
    return PasswordResetCodeResult.fromJson(_unwrapData(resp.data));
  }

  /// The mnemonic stays on-device. Only its public fingerprint is submitted.
  Future<AuthResult> reactivateAccount({
    required String phone,
    required String code,
    required String keyFingerprint,
  }) async {
    final resp =
        await _client.dio.post('/auth/account-recovery/reactivate', data: {
      'phone': phone,
      'code': code,
      'keyFingerprint': keyFingerprint,
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
      if (resp.data is Map && resp.data['code'] == 0) {
        final data = resp.data['data'] as Map<String, dynamic>?;
        if (data == null) return null;
        return AccountInfo(
          userId: data['userId'] as String? ?? '',
          phoneTail: data['phoneTail'] as String? ?? '',
          nickname: data['nickname'] as String? ?? '',
          avatarUrl: data['avatarUrl'] as String? ?? '',
          hasCloudSync: data['hasCloudSync'] == true,
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
    final body = resp.data;
    if (body is Map && body['code'] == 0 && body['data'] is Map) {
      return AccountInfo.fromJson(
        Map<String, dynamic>.from(body['data'] as Map),
      );
    }
    return fetchAccountInfo();
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
    final body = resp.data;
    if (body is Map && body['code'] == 0 && body['data'] is Map) {
      final data = Map<String, dynamic>.from(body['data'] as Map);
      final avatarUrl = data['avatarUrl'] as String? ?? '';
      if (avatarUrl.isNotEmpty) return avatarUrl;
    }
    throw StateError('头像上传失败');
  }

  Map<String, dynamic> _unwrapData(dynamic body) {
    if (body is! Map) {
      throw StateError('服务器响应格式异常');
    }
    final code = (body['code'] as num?)?.toInt() ?? 0;
    if (code != 0) {
      throw StateError(
        (body['message'] ?? body['msg'])?.toString() ?? '请求失败',
      );
    }
    final data = body['data'];
    if (data is Map) return Map<String, dynamic>.from(data);
    throw StateError('服务器响应缺少 data 字段');
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
    required this.phoneTail,
    required this.nickname,
    required this.avatarUrl,
    required this.hasCloudSync,
  });

  final String userId;
  final String phoneTail;
  final String nickname;
  final String avatarUrl;
  final bool hasCloudSync;

  factory AccountInfo.fromJson(Map<String, dynamic> j) => AccountInfo(
        userId: j['userId'] as String? ?? '',
        phoneTail: j['phoneTail'] as String? ?? '',
        nickname: j['nickname'] as String? ?? '',
        avatarUrl: j['avatarUrl'] as String? ?? '',
        hasCloudSync: j['hasCloudSync'] == true,
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

/// 把 DioException 转成用户友好的错误文本
String friendlyAuthError(Object e) {
  if (e is DioException) {
    final data = e.response?.data;
    if (data is Map && data['message'] != null) {
      return data['message'].toString();
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
  if (e is StateError) return e.message;
  return e.toString();
}
