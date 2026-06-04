import 'package:dio/dio.dart';

import 'api_client.dart';

/// 认证 API：注册 / 登录 / 刷新 Token / 注销。
///
/// 后端约定：
/// - {@code credType}：phone 或 email
/// - 密码 8-64 位
/// - 成功返回 {accessToken, refreshToken, accessExpiresIn, userId}
class AuthApi {
  AuthApi({required ApiClient client}) : _client = client;
  final ApiClient _client;

  /// 注册新账号
  Future<AuthResult> register({
    required String credType,        // 'phone' / 'email'
    required String identifier,
    required String password,
    String? nickname,
  }) async {
    final resp = await _client.dio.post('/auth/register', data: {
      'credType': credType,
      'identifier': identifier,
      'password': password,
      if (nickname != null) 'nickname': nickname,
    });
    return AuthResult.fromJson(resp.data['data'] as Map<String, dynamic>);
  }

  /// 登录现有账号
  Future<AuthResult> login({
    required String credType,
    required String identifier,
    required String password,
  }) async {
    final resp = await _client.dio.post('/auth/login', data: {
      'credType': credType,
      'identifier': identifier,
      'password': password,
    });
    return AuthResult.fromJson(resp.data['data'] as Map<String, dynamic>);
  }

  /// 刷新 Access Token
  Future<AuthResult> refresh(String refreshToken) async {
    final resp = await _client.dio.post('/auth/refresh', data: {
      'refreshToken': refreshToken,
    });
    return AuthResult.fromJson(resp.data['data'] as Map<String, dynamic>);
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
}

class AuthResult {
  const AuthResult({
    required this.userId,
    required this.accessToken,
    required this.refreshToken,
    required this.accessExpiresIn,
  });

  final String userId;
  final String accessToken;
  final String refreshToken;
  final int accessExpiresIn;

  factory AuthResult.fromJson(Map<String, dynamic> j) => AuthResult(
        userId: j['userId'] as String,
        accessToken: j['accessToken'] as String,
        refreshToken: j['refreshToken'] as String,
        accessExpiresIn: (j['accessExpiresIn'] as num).toInt(),
      );
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
  return e.toString();
}
