class ApiResponseException implements Exception {
  const ApiResponseException(this.code, this.message);

  final int code;
  final String message;

  @override
  String toString() => message;
}

Object? unwrapApiResponse(Object? body) {
  if (body is! Map || !body.containsKey('code')) return body;

  final code = (body['code'] as num?)?.toInt() ?? -1;
  if (code != 0) {
    throw ApiResponseException(
      code,
      (body['msg'] ?? body['message'])?.toString() ?? '请求失败',
    );
  }
  return body['data'];
}

Map<String, dynamic> requireApiMap(Object? data) {
  if (data is Map) return Map<String, dynamic>.from(data);
  throw const FormatException('服务器响应缺少数据');
}
