import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';

import 'package:health_reset_plan/core/network/api_response.dart';
import 'package:health_reset_plan/core/network/auth_api.dart';

void main() {
  test('unknown captcha errors are hidden behind a stable message', () {
    expect(
      friendlyAuthError(
        DioException(
          requestOptions: RequestOptions(path: '/auth/captcha/create'),
          type: DioExceptionType.unknown,
        ),
      ),
      '安全验证请求失败，请点击刷新重试',
    );
    expect(
      friendlyAuthError(
        DioException(
          requestOptions: RequestOptions(path: '/auth/captcha/create'),
          error: const ApiResponseException(50001, 'unknown'),
        ),
      ),
      '安全验证请求失败，请点击刷新重试',
    );
  });
}
