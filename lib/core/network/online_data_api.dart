import 'package:dio/dio.dart';

import 'api_client.dart';

class OnlineDataSnapshot {
  const OnlineDataSnapshot({required this.version, required this.tables});

  final int version;
  final Map<String, List<Map<String, Object?>>> tables;
}

class OnlineDataApi {
  OnlineDataApi({required ApiClient client}) : _client = client;

  final ApiClient _client;

  Future<OnlineDataSnapshot> load() async {
    final response = await _client.dio.get('/data');
    return _snapshot(response.data);
  }

  Future<OnlineDataSnapshot> save(
    int version,
    Map<String, List<Map<String, Object?>>> tables,
  ) async {
    try {
      final response = await _client.dio.put('/data', data: {
        'version': version,
        'data': tables,
      });
      final body = response.data;
      if (body is Map && body['code'] == 40901) {
        throw const OnlineDataConflictException();
      }
      return _snapshot(response.data);
    } on DioException catch (error) {
      final body = error.response?.data;
      if (body is Map && body['code'] == 40901) {
        throw const OnlineDataConflictException();
      }
      rethrow;
    }
  }

  OnlineDataSnapshot _snapshot(Object? body) {
    if (body is! Map || body['code'] != 0 || body['data'] is! Map) {
      throw const FormatException('在线数据响应格式错误');
    }
    final payload = Map<String, dynamic>.from(body['data'] as Map);
    final rawTables = payload['data'];
    final tables = <String, List<Map<String, Object?>>>{};
    if (rawTables is Map) {
      for (final entry in rawTables.entries) {
        final rows = entry.value;
        if (rows is List) {
          tables['${entry.key}'] = rows
              .whereType<Map>()
              .map((row) => row.map(
                    (key, value) => MapEntry('$key', value as Object?),
                  ))
              .toList();
        }
      }
    }
    return OnlineDataSnapshot(
      version: (payload['version'] as num?)?.toInt() ?? 0,
      tables: tables,
    );
  }
}

class OnlineDataConflictException implements Exception {
  const OnlineDataConflictException();

  @override
  String toString() => '数据已在其他设备更新，请重新操作';
}
