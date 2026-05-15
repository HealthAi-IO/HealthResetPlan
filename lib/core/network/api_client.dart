import 'package:dio/dio.dart';

/// 后端 API Dio 客户端骨架。
///
/// 注意：上传到服务端的健康敏感数据必须先经过 [CryptoService] 加密。
/// 本类只负责 HTTP 通信，不处理加密 / 解密。
class ApiClient {
  ApiClient({String baseUrl = 'https://api.jkcqplan.com/api/v1'})
      : _dio = Dio(
          BaseOptions(
            baseUrl: baseUrl,
            connectTimeout: const Duration(seconds: 5),
            receiveTimeout: const Duration(seconds: 30),
            sendTimeout: const Duration(seconds: 30),
            headers: const {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
          ),
        );

  final Dio _dio;

  Dio get dio => _dio;

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
}
