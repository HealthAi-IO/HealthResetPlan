import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_reset_plan/core/auth/user_session.dart';
import 'package:health_reset_plan/core/crypto/crypto_service.dart';
import 'package:health_reset_plan/core/crypto/key_vault.dart';
import 'package:health_reset_plan/core/data/chat_repository.dart';
import 'package:health_reset_plan/core/data/health_models.dart';
import 'package:health_reset_plan/core/data/health_repository.dart';
import 'package:health_reset_plan/core/network/api_client.dart';
import 'package:health_reset_plan/core/storage/app_database.dart';
import 'package:health_reset_plan/core/sync/sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  test('upload reject keeps the local row dirty', () async {
    final database = _MemoryAppDatabase();
    await database.insert('plan', _planRow());
    final service = await _service(
      database,
      pushResponse: {
        'accepted': 0,
        'rejected': [
          {'table': 'plan', 'clientId': 'plan-1'}
        ],
      },
    );

    final result = await service.sync();

    expect(result.hasError, isFalse);
    expect((await database.query('plan')).single['is_dirty'], 1);
  });

  test('delete reject keeps the deletion in the sync queue', () async {
    final database = _MemoryAppDatabase();
    await database.insert('sync_queue', {
      'table_name': 'plan',
      'op': 'delete',
      'payload_json':
          '{"table":"plan","clientId":"plan-1","version":2,"clientUpdatedAt":2}',
      'created_at': 2,
      'updated_at': 2,
    });
    final service = await _service(
      database,
      pushResponse: {
        'accepted': 0,
        'rejected': [
          {'table': 'plan', 'clientId': 'plan-1'}
        ],
      },
    );

    final result = await service.sync();

    expect(result.hasError, isFalse);
    expect(await database.query('sync_queue'), hasLength(1));
  });

  test('pull merge failure does not advance the cursor', () async {
    SharedPreferences.setMockInitialValues({'sync_last_ms': 123});
    final database = _MemoryAppDatabase();
    final service = await _service(
      database,
      pullResponse: {
        'items': [
          {
            'table': 'plan',
            'clientId': 'plan-remote',
            'version': 1,
            'clientUpdatedAt': 456,
            'cipher': 'invalid',
            'iv': 'invalid',
            'tag': 'invalid',
            'alg': 'aes-256-gcm:v2',
            'deleted': false,
          }
        ],
        'serverTime': 456,
        'hasMore': false,
      },
    );

    final result = await service.sync();

    expect(result.hasError, isTrue);
    expect(await service.getLastSyncMs(), 123);
  });

  test('web windows and android reports merge as a union', () async {
    const storage = FlutterSecureStorage();
    final keyVault = KeyVault(storage: storage);
    await keyVault.generate();
    await keyVault.markBackedUp();
    final crypto = AesGcmCryptoService(keyVault: keyVault);
    final remoteItems = <Map<String, Object?>>[];
    for (var index = 1; index <= 4; index++) {
      final clientId = 'web-report-$index';
      final payload = {
        'user_id': kLocalUserId,
        'client_id': clientId,
        'image_path': '',
        'report_time': index,
        'summary': 'web-$index',
        'raw_text': '',
        'structured_json': '{}',
        'provider': 'test',
        'version': 1,
        'created_at': index,
        'updated_at': index,
      };
      final encrypted = await crypto.encryptString(
        jsonEncode(payload),
        aad: utf8.encode(
          'hrp-sync:v2:${UserSession.instance.userId ?? ''}:health_report:$clientId:1',
        ),
      );
      remoteItems.add({
        'table': 'health_report',
        'clientId': clientId,
        'version': 1,
        'clientUpdatedAt': index,
        ...encrypted.toJson()..['alg'] = 'aes-256-gcm:v2',
        'deleted': false,
      });
    }

    final database = _MemoryAppDatabase();
    await database.insert('health_report', _reportRow('android-report-1'));
    final service = await _service(
      database,
      keyVault: keyVault,
      pullResponse: {
        'items': remoteItems,
        'serverTime': 200,
        'hasMore': false,
      },
    );

    final result = await service.sync();

    expect(result.hasError, isFalse);
    final reports = await database.query('health_report');
    expect(reports, hasLength(5));
    expect(
      reports.map((row) => row['client_id']),
      containsAll([
        'android-report-1',
        'web-report-1',
        'web-report-2',
        'web-report-3',
        'web-report-4',
      ]),
    );
  });

  test('web AI transport aliases are not written into SQLite rows', () async {
    const storage = FlutterSecureStorage();
    final keyVault = KeyVault(storage: storage);
    await keyVault.generate();
    await keyVault.markBackedUp();
    final crypto = AesGcmCryptoService(keyVault: keyVault);
    const clientId = 'session-1';
    final encrypted = await crypto.encryptString(
      jsonEncode({
        'session_uuid': clientId,
        'sessionUuid': clientId,
        'title': 'test',
        'provider': 'qwen',
        'version': 1,
        'created_at': 1,
        'updated_at': 1,
      }),
      aad: utf8.encode(
        'hrp-sync:v2:${UserSession.instance.userId ?? ''}:ai_session:$clientId:1',
      ),
    );
    final database = _MemoryAppDatabase();
    final service = await _service(
      database,
      keyVault: keyVault,
      pullResponse: {
        'items': [
          {
            'table': 'ai_session',
            'clientId': clientId,
            'version': 1,
            'clientUpdatedAt': 1,
            ...encrypted.toJson()..['alg'] = 'aes-256-gcm:v2',
            'deleted': false,
          }
        ],
        'serverTime': 200,
        'hasMore': false,
      },
    );

    final result = await service.sync();

    expect(result.hasError, isFalse);
    final row = (await database.query('ai_session')).single;
    expect(row['session_uuid'], clientId);
    expect(row.containsKey('sessionUuid'), isFalse);
  });

  test('mixed account keys stop sync with a recovery prompt', () async {
    final service = await _service(
      _MemoryAppDatabase(),
      keyStatusResponse: {
        'matchingKeyRecords': 1,
        'otherKeyRecords': 4,
      },
    );

    final result = await service.sync();

    expect(result.hasError, isTrue);
    expect(result.error, contains('24 词助记词'));
  });

  test('restoring the previous device key may resolve a mixed-key account',
      () async {
    const storage = FlutterSecureStorage();
    final keyVault = KeyVault(storage: storage);
    await keyVault.generate();
    final previousFingerprint = await keyVault.publicFingerprint();
    await keyVault.generate();
    await keyVault.markBackedUp();
    final currentFingerprint = await keyVault.publicFingerprint();
    final service = await _service(
      _MemoryAppDatabase(),
      keyVault: keyVault,
      keyStatusResponse: {
        'matchingKeyRecords': 4,
        'otherKeyRecords': 1,
      },
    );
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      'sync_last_key_fingerprint',
      previousFingerprint!,
    );
    await preferences.setString(
      'sync_migration_key_fingerprint',
      currentFingerprint!,
    );

    final result = await service.sync();

    expect(result.hasError, isFalse);
  });
}

Map<String, Object?> _planRow() => {
      'id': 1,
      'user_id': kLocalUserId,
      'client_id': 'plan-1',
      'type': 'meal',
      'plan_date': 1,
      'payload_json': '{}',
      'ai_provider': '',
      'ai_model': '',
      'version': 1,
      'is_dirty': 1,
      'sync_at': 0,
      'created_at': 1,
      'updated_at': 1,
    };

Map<String, Object?> _reportRow(String clientId) => {
      'id': 1,
      'user_id': kLocalUserId,
      'client_id': clientId,
      'image_path': '',
      'report_time': 1,
      'summary': 'android',
      'raw_text': '',
      'structured_json': '{}',
      'provider': 'test',
      'version': 1,
      'is_dirty': 1,
      'sync_at': 0,
      'created_at': 1,
      'updated_at': 1,
    };

Future<SyncService> _service(
  _MemoryAppDatabase database, {
  KeyVault? keyVault,
  Map<String, Object?> pushResponse = const {
    'accepted': 0,
    'rejected': [],
  },
  Map<String, Object?> keyStatusResponse = const {
    'matchingKeyRecords': 0,
    'otherKeyRecords': 0,
  },
  Map<String, Object?> pullResponse = const {
    'items': [],
    'serverTime': 200,
    'hasMore': false,
  },
}) async {
  const storage = FlutterSecureStorage();
  final vault = keyVault ?? KeyVault(storage: storage);
  if (keyVault == null) {
    await vault.generate();
    await vault.markBackedUp();
  }
  final preferences = await SharedPreferences.getInstance();
  await preferences.setString(
    'sync_last_key_fingerprint',
    (await vault.publicFingerprint())!,
  );
  final apiClient = ApiClient(baseUrl: 'https://test.invalid/api/v1');
  apiClient.dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        final data = options.path.endsWith('/sync/push')
            ? pushResponse
            : options.path.endsWith('/sync/key-status')
                ? keyStatusResponse
                : pullResponse;
        handler.resolve(
          Response(
            requestOptions: options,
            statusCode: 200,
            data: {'code': 0, 'msg': 'ok', 'data': data},
          ),
        );
      },
    ),
  );
  return SyncService(
    apiClient: apiClient,
    cryptoService: AesGcmCryptoService(keyVault: vault),
    keyVault: vault,
    database: database,
    repository: HealthRepository(database: database),
    chatRepository: ChatRepository(database: database),
  );
}

class _MemoryAppDatabase implements AppDatabase {
  static const _tables = [
    'user_profile',
    'health_indicator',
    'plan',
    'clock_record',
    'reminder',
    'health_report',
    'meal_record',
    'ai_session',
    'ai_message',
    'sync_queue',
  ];

  final Map<String, List<Map<String, Object?>>> _data = {
    for (final table in _tables) table: <Map<String, Object?>>[],
  };

  @override
  Future<AppDatabase> open() async => this;

  @override
  Future<void> close() async {}

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    String? where,
    List<Object?>? whereArgs,
    String? orderBy,
    int? limit,
  }) async {
    var rows =
        _table(table).map((row) => Map<String, Object?>.from(row)).toList();
    if (where != null) {
      rows = rows.where((row) => _matches(row, where, whereArgs)).toList();
    }
    if (orderBy != null) {
      final parts = orderBy.split(RegExp(r'\s+'));
      final key = parts.first;
      rows.sort((left, right) =>
          '${left[key] ?? ''}'.compareTo('${right[key] ?? ''}'));
    }
    if (limit != null && rows.length > limit) rows = rows.sublist(0, limit);
    return rows;
  }

  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    bool replace = false,
  }) async {
    final rows = _table(table);
    final row = Map<String, Object?>.from(values);
    row['id'] ??= rows.length + 1;
    rows.add(row);
    return row['id'] as int;
  }

  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    var count = 0;
    for (final row in _table(table)) {
      if (where == null || _matches(row, where, whereArgs)) {
        row.addAll(values);
        count++;
      }
    }
    return count;
  }

  @override
  Future<int> delete(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    final rows = _table(table);
    final before = rows.length;
    if (where == null) {
      rows.clear();
    } else {
      rows.removeWhere((row) => _matches(row, where, whereArgs));
    }
    return before - rows.length;
  }

  @override
  Future<int> count(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) async =>
      (await query(table, where: where, whereArgs: whereArgs)).length;

  @override
  Future<T> transaction<T>(Future<T> Function(AppDatabase txn) action) =>
      action(this);

  List<Map<String, Object?>> _table(String table) =>
      _data.putIfAbsent(table, () => []);

  bool _matches(
    Map<String, Object?> row,
    String where,
    List<Object?>? args,
  ) {
    if (args == null) return false;
    final clauses = where.split(RegExp(r'\s+AND\s+', caseSensitive: false));
    if (clauses.length != args.length) return false;
    for (var index = 0; index < clauses.length; index++) {
      final match = RegExp(r'^\s*([a-zA-Z0-9_]+)\s*=\s*\?\s*$')
          .firstMatch(clauses[index]);
      if (match == null || '${row[match.group(1)]}' != '${args[index]}') {
        return false;
      }
    }
    return true;
  }
}
