import 'package:dio/dio.dart';

import '../auth/user_session.dart';
import '../config/app_config.dart';
import 'api_response.dart';

const _skipAuthRefreshKey = 'skipAuthRefresh';

/// 后端 API Dio 客户端骨架。
///
/// 健康敏感数据由服务端统一加密后存储。
/// 本类只负责 HTTP 通信，不处理加密 / 解密。
class ApiClient {
  ApiClient({
    String baseUrl = apiBaseUrl,
    HttpClientAdapter? adapter,
  })  : _refreshDio = Dio(
          BaseOptions(
            baseUrl: baseUrl,
            connectTimeout: const Duration(seconds: 3),
            receiveTimeout: const Duration(seconds: 15),
            sendTimeout: const Duration(seconds: 15),
            headers: const {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
          ),
        ),
        _dio = Dio(
          BaseOptions(
            baseUrl: baseUrl,
            // 严格控制超时，避免后端没起时 UI 长时间卡死
            connectTimeout: const Duration(seconds: 3),
            receiveTimeout: const Duration(seconds: 15),
            sendTimeout: const Duration(seconds: 15),
            headers: const {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
          ),
        ) {
    if (adapter != null) {
      _dio.httpClientAdapter = adapter;
      _refreshDio.httpClientAdapter = adapter;
    }
    _dio.interceptors.add(
      InterceptorsWrapper(
        onResponse: _handleResponse,
        onError: _handleAuthError,
      ),
    );
  }

  final Dio _dio;
  final Dio _refreshDio;
  Future<_RefreshedSession?>? _refreshing;
  Future<void>? _expiringSession;
  Future<void> Function()? _sessionExpiredHandler;

  Dio get dio => _dio;

  void setSessionExpiredHandler(Future<void> Function() handler) {
    _sessionExpiredHandler = handler;
  }

  void setAccessToken(String? token) {
    if (token == null || token.isEmpty) {
      _dio.options.headers.remove('Authorization');
    } else {
      _dio.options.headers['Authorization'] = 'Bearer $token';
    }
  }

  void setDeviceHeaders({
    required String deviceId,
    required String platform,
    required String appVersion,
  }) {
    _dio.options.headers
      ..['X-Device-Id'] = deviceId
      ..['X-Platform'] = platform
      ..['X-App-Version'] = appVersion;
  }

  Future<void> _handleResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) async {
    try {
      response.data = unwrapApiResponse(response.data);
      handler.next(response);
    } on ApiResponseException catch (error) {
      if ((error.code == 401 || error.code == 40102) &&
          !_isAuthPath(response.requestOptions.path)) {
        await _clearSessionAfterRefreshFailure();
      }
      handler.reject(
        DioException(
          requestOptions: response.requestOptions,
          response: response,
          type: DioExceptionType.badResponse,
          message: error.message,
          error: error,
        ),
      );
    }
  }

  Future<void> _handleAuthError(
    DioException error,
    ErrorInterceptorHandler handler,
  ) async {
    if (!_isProtectedUnauthorized(error)) {
      handler.next(error);
      return;
    }

    if (!_canRefresh(error)) {
      await _clearSessionAfterRefreshFailure();
      handler.next(error);
      return;
    }

    try {
      final refreshed = await _refreshAccessToken();
      if (refreshed == null) {
        await _clearSessionAfterRefreshFailure();
        handler.next(error);
        return;
      }

      final options = _cloneRequestOptions(error.requestOptions);
      options.extra[_skipAuthRefreshKey] = true;
      options.headers['Authorization'] = 'Bearer ${refreshed.accessToken}';
      final response = await _dio.fetch<dynamic>(options);
      handler.resolve(response);
    } catch (_) {
      await _clearSessionAfterRefreshFailure();
      handler.next(error);
    }
  }

  bool _isProtectedUnauthorized(DioException error) {
    final status = error.response?.statusCode;
    if (status != 401) return false;
    if (error.requestOptions.extra[_skipAuthRefreshKey] == true) return false;

    if (_isAuthPath(error.requestOptions.path)) return false;

    return true;
  }

  bool _isAuthPath(String path) =>
      path.contains('/auth/login') ||
      path.contains('/auth/register') ||
      path.contains('/auth/sms/register') ||
      path.contains('/auth/refresh') ||
      path.contains('/auth/logout');

  bool _canRefresh(DioException error) {
    if (!_isProtectedUnauthorized(error)) return false;
    final refreshToken = UserSession.instance.refreshToken;
    return refreshToken != null && refreshToken.isNotEmpty;
  }

  Future<void> _clearSessionAfterRefreshFailure() async {
    final existing = _expiringSession;
    if (existing != null) return existing;

    final task = _expireSession();
    _expiringSession = task;
    try {
      await task;
    } finally {
      if (identical(_expiringSession, task)) _expiringSession = null;
    }
  }

  Future<void> _expireSession() async {
    final handler = _sessionExpiredHandler;
    if (handler != null) {
      await handler();
    } else {
      await UserSession.instance.signOut(sessionExpired: true);
    }
    setAccessToken(null);
  }

  Future<_RefreshedSession?> _refreshAccessToken() {
    final existing = _refreshing;
    if (existing != null) return existing;

    final task = _doRefreshAccessToken();
    _refreshing = task;
    return task.whenComplete(() => _refreshing = null);
  }

  Future<_RefreshedSession?> _doRefreshAccessToken() async {
    final refreshToken = UserSession.instance.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) return null;

    final resp = await _refreshDio.post('/auth/refresh', data: {
      'refreshToken': refreshToken,
    });
    final body = resp.data;
    if (body is! Map || body['code'] != 0 || body['data'] is! Map) {
      return null;
    }

    final data = Map<String, dynamic>.from(body['data'] as Map);
    final userId = data['userId'] as String? ?? UserSession.instance.userId;
    final accessToken = data['accessToken'] as String?;
    final nextRefreshToken = data['refreshToken'] as String?;
    if (userId == null ||
        userId.isEmpty ||
        accessToken == null ||
        accessToken.isEmpty ||
        nextRefreshToken == null ||
        nextRefreshToken.isEmpty) {
      return null;
    }

    await UserSession.instance.setAccountSession(
      userId: userId,
      accessToken: accessToken,
      refreshToken: nextRefreshToken,
      nickname: UserSession.instance.name,
    );
    setAccessToken(accessToken);
    return _RefreshedSession(accessToken: accessToken);
  }

  RequestOptions _cloneRequestOptions(RequestOptions source) {
    return Options(
      method: source.method,
      sendTimeout: source.sendTimeout,
      receiveTimeout: source.receiveTimeout,
      extra: Map<String, dynamic>.from(source.extra),
      headers: Map<String, dynamic>.from(source.headers),
      responseType: source.responseType,
      contentType: source.contentType,
      validateStatus: source.validateStatus,
      receiveDataWhenStatusError: source.receiveDataWhenStatusError,
      followRedirects: source.followRedirects,
      maxRedirects: source.maxRedirects,
      requestEncoder: source.requestEncoder,
      responseDecoder: source.responseDecoder,
      listFormat: source.listFormat,
    ).compose(
      _dio.options,
      source.path,
      data: source.data,
      queryParameters: Map<String, dynamic>.from(source.queryParameters),
      cancelToken: source.cancelToken,
      onReceiveProgress: source.onReceiveProgress,
      onSendProgress: source.onSendProgress,
    );
  }
}

class _RefreshedSession {
  const _RefreshedSession({required this.accessToken});

  final String accessToken;
}
