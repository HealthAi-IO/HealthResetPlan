import 'package:flutter_test/flutter_test.dart';
import 'package:health_reset_plan/core/network/api_response.dart';

void main() {
  test('成功响应只返回 data', () {
    expect(
      unwrapApiResponse({
        'code': 0,
        'msg': '成功',
        'data': {'value': 1},
      }),
      {'value': 1},
    );
  });

  test('失败响应统一抛出业务异常', () {
    expect(
      () => unwrapApiResponse({'code': 40001, 'msg': '参数错误'}),
      throwsA(
        isA<ApiResponseException>()
            .having((error) => error.code, 'code', 40001)
            .having((error) => error.message, 'message', '参数错误'),
      ),
    );
  });

  test('非标准响应保持原样', () {
    expect(unwrapApiResponse(const [1, 2]), const [1, 2]);
  });
}
