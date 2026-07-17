import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../crypto/crypto_service.dart';
import '../crypto/key_vault.dart';
import '../auth/user_session.dart';
import '../data/health_models.dart';
import '../data/health_repository.dart';
import '../network/api_client.dart';
import '../storage/app_database.dart';
import '../storage/report_image_storage.dart';

class SyncResult {
  const SyncResult({
    required this.pushed,
    required this.pulled,
    this.error,
    this.attempts = 1,
  });

  final int pushed;
  final int pulled;
  final String? error;
  final int attempts;

  bool get hasError => error != null;
}

class _TableConfig {
  const _TableConfig({
    required this.table,
    required this.metaKeys,
    this.profileSingleton = false,
  });

  final String table;
  final List<String> metaKeys;
  final bool profileSingleton;
}

/// Client-side encrypted incremental sync.
///
/// Each synced row is serialized as one JSON object, encrypted locally, then
/// uploaded. The server only stores ciphertext and merge metadata.
class SyncService {
  SyncService({
    required this.apiClient,
    required this.cryptoService,
    required this.keyVault,
    required this.database,
    required this.repository,
  });

  final ApiClient apiClient;
  final CryptoService cryptoService;
  final KeyVault keyVault;
  final AppDatabase database;
  final HealthRepository repository;
  Future<SyncResult>? _activeSync;

  static const String _kLastSyncMs = 'sync_last_ms';
  static const String _kSyncEnabled = 'sync_enabled';
  static const String _kDeviceId = 'sync_device_id';
  static const String _kLastKeyFingerprint = 'sync_last_key_fingerprint';
  static const String _kSyncAccountId = 'sync_account_id';
  static const _uuid = Uuid();

  static const _tables = [
    _TableConfig(
      table: 'user_profile',
      metaKeys: [],
      profileSingleton: true,
    ),
    _TableConfig(
      table: 'health_indicator',
      metaKeys: ['type'],
    ),
    _TableConfig(
      table: 'plan',
      metaKeys: [],
    ),
    _TableConfig(
      table: 'clock_record',
      metaKeys: [],
    ),
    _TableConfig(
      table: 'reminder',
      metaKeys: [],
    ),
    _TableConfig(
      table: 'health_report',
      metaKeys: [],
    ),
    _TableConfig(
      table: 'meal_record',
      metaKeys: [],
    ),
  ];

  static final Map<String, _TableConfig> _configByTable = {
    for (final config in _tables) config.table: config,
  };

  Future<bool> isSyncEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kSyncEnabled) ?? false;
  }

  Future<void> setSyncEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    if (enabled) {
      final state = await keyVault.status();
      if (state != KeyVaultState.ready) {
        await prefs.setBool(_kSyncEnabled, false);
        throw StateError(state.syncMessage);
      }
    }
    await prefs.setBool(_kSyncEnabled, enabled);
  }

  /// 隔离同一设备上的不同账号，避免把上一个账号的本地数据或密钥上传到新账号。
  Future<bool> bindToAccount(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final owner = prefs.getString(_kSyncAccountId);
    if (owner == null || owner.isEmpty) {
      await prefs.setString(_kSyncAccountId, userId);
      return false;
    }
    if (owner == userId) return false;
    await _clearLocalSyncedData();
    await prefs.setString(_kSyncAccountId, userId);
    await prefs.setBool(_kSyncEnabled, false);
    await prefs.remove(_kLastSyncMs);
    await prefs.remove(_kLastKeyFingerprint);
    return true;
  }

  Future<int> getLastSyncMs() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kLastSyncMs) ?? 0;
  }

  Future<void> resetLastSyncMs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kLastSyncMs);
  }

  Future<void> _saveLastSyncMs(int ms) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kLastSyncMs, ms);
  }

  Future<void> _saveLastKeyFingerprint(String keyFingerprint) async {
    if (keyFingerprint.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastKeyFingerprint, keyFingerprint);
  }

  Future<void> _prepareKeyFingerprintChange(String keyFingerprint) async {
    if (keyFingerprint.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final lastKeyFingerprint = prefs.getString(_kLastKeyFingerprint) ?? '';
    if (lastKeyFingerprint == keyFingerprint) {
      return;
    }

    if (lastKeyFingerprint.isEmpty && await getLastSyncMs() == 0) {
      return;
    }

    await resetLastSyncMs();
    await _markAllLocalRowsDirty();
  }

  Future<String> _getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_kDeviceId);
    if (existing != null && existing.isNotEmpty) return existing;

    final next = _uuid.v4();
    await prefs.setString(_kDeviceId, next);
    return next;
  }

  Future<String> _keyFingerprintOrEmpty() async =>
      await keyVault.publicFingerprint() ?? '';

  Future<SyncResult> sync() {
    final active = _activeSync;
    if (active != null) return active;

    final task = _performSync();
    _activeSync = task;
    return task.whenComplete(() => _activeSync = null);
  }

  Future<SyncResult> _performSync() async {
    try {
      return await _runWithRetry(() async {
        await _requireReadyKey();
        final keyFingerprint = await _keyFingerprintOrEmpty();
        await _prepareKeyFingerprintChange(keyFingerprint);
        final pushed = await _push();
        final pulled = await _pull();
        await _saveLastKeyFingerprint(keyFingerprint);
        return SyncResult(pushed: pushed, pulled: pulled);
      });
    } catch (e) {
      return SyncResult(pushed: 0, pulled: 0, error: _friendlySyncError(e));
    }
  }

  Future<SyncResult> restoreFromCloud({bool replaceLocal = false}) async {
    try {
      return await _runWithRetry(() async {
        await _requireReadyKey();
        await resetLastSyncMs();
        if (replaceLocal) {
          await _clearLocalSyncedData();
        }
        final pulled = await _pull();
        return SyncResult(pushed: 0, pulled: pulled);
      });
    } catch (e) {
      return SyncResult(pushed: 0, pulled: 0, error: _friendlySyncError(e));
    }
  }

  Future<void> _requireReadyKey() async {
    final state = await keyVault.status();
    if (state != KeyVaultState.ready) throw StateError(state.syncMessage);
  }

  Future<SyncResult> _runWithRetry(
    Future<SyncResult> Function() action,
  ) async {
    Object? lastError;
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        final result = await action();
        return SyncResult(
          pushed: result.pushed,
          pulled: result.pulled,
          error: result.error,
          attempts: attempt,
        );
      } catch (e) {
        lastError = e;
        if (!_isRetryable(e) || attempt == 3) break;
        await Future<void>.delayed(
            Duration(milliseconds: 450 * pow(2, attempt - 1).toInt()));
      }
    }
    return SyncResult(
      pushed: 0,
      pulled: 0,
      error: _friendlySyncError(lastError),
      attempts: 3,
    );
  }

  Future<void> _clearLocalSyncedData() async {
    final db = await database.open();
    for (final config in _tables) {
      await db.delete(config.table);
    }
    await db.delete('sync_queue');
    repository.signalChanged();
  }

  Future<void> _markAllLocalRowsDirty() async {
    final db = await database.open();
    for (final config in _tables) {
      await db.update(
        config.table,
        {'is_dirty': 1},
        where: 'user_id = ?',
        whereArgs: [kLocalUserId],
      );
    }
  }

  Future<int> _push() async {
    final db = await database.open();
    var totalAccepted = await _pushDeletes(db);

    for (final config in _tables) {
      final rows = await db.query(config.table);
      final dirtyRows = rows
          .where((row) => (_asInt(row['is_dirty']) ?? 1) == 1)
          .where(
              (row) => row['user_id'] == null || row['user_id'] == kLocalUserId)
          .toList();
      if (dirtyRows.isEmpty) continue;

      final items = <Map<String, dynamic>>[];
      final rowsToMark = <String>[];

      for (final row in dirtyRows) {
        final prepared = await _ensureClientId(db, config, row);
        final clientId = prepared['client_id'] as String;
        final payload = await _buildEncryptedRowPayload(config.table, prepared);
        final version = _asInt(prepared['version']) ?? 0;
        final enc = await cryptoService.encryptString(
          jsonEncode(payload),
          aad: _syncAad(config.table, clientId, version),
        );

        items.add({
          'table': config.table,
          'clientId': clientId,
          'version': version,
          'clientUpdatedAt': _asInt(prepared['updated_at']) ??
              DateTime.now().millisecondsSinceEpoch,
          ...enc.toJson()..['alg'] = 'aes-256-gcm:v2',
          'deleted': false,
          'meta': _buildMeta(config, prepared),
        });
        rowsToMark.add(clientId);
      }

      final batchSize = config.table == 'health_report' ? 1 : 50;
      for (var start = 0; start < items.length; start += batchSize) {
        final end = min(start + batchSize, items.length);
        final batch = items.sublist(start, end);
        totalAccepted += await _pushItems(batch);

        final now = DateTime.now().millisecondsSinceEpoch;
        for (final clientId in rowsToMark.sublist(start, end)) {
          await db.update(
            config.table,
            {'is_dirty': 0, 'sync_at': now},
            where: 'client_id = ?',
            whereArgs: [clientId],
          );
        }
      }
    }

    return totalAccepted;
  }

  Future<int> _pushDeletes(AppDatabase db) async {
    final rows = await db.query(
      'sync_queue',
      where: 'op = ?',
      whereArgs: ['delete'],
      orderBy: 'created_at ASC',
      limit: 200,
    );
    if (rows.isEmpty) return 0;

    final items = <Map<String, dynamic>>[];
    final queuedIds = <Object?>[];
    for (final row in rows) {
      final payload = jsonDecode(row['payload_json'] as String? ?? '{}');
      if (payload is! Map) continue;
      final table =
          payload['table'] as String? ?? row['table_name'] as String? ?? '';
      final clientId = payload['clientId'] as String? ?? '';
      if (!_configByTable.containsKey(table) || clientId.isEmpty) continue;

      final version = _asInt(payload['version']) ?? 0;
      final enc = await cryptoService.encryptString(
        jsonEncode({'deleted': true}),
        aad: _syncAad(table, clientId, version),
      );
      items.add({
        'table': table,
        'clientId': clientId,
        'version': version,
        'clientUpdatedAt': _asInt(payload['clientUpdatedAt']) ??
            _asInt(row['updated_at']) ??
            DateTime.now().millisecondsSinceEpoch,
        ...enc.toJson()..['alg'] = 'aes-256-gcm:v2',
        'deleted': true,
        'meta': {'deleted': true},
      });
      queuedIds.add(row['id']);
    }
    if (items.isEmpty) return 0;

    var accepted = 0;
    const batchSize = 50;
    for (var start = 0; start < items.length; start += batchSize) {
      final end = min(start + batchSize, items.length);
      accepted += await _pushItems(items.sublist(start, end));
      for (final id in queuedIds.sublist(start, end)) {
        await db.delete('sync_queue', where: 'id = ?', whereArgs: [id]);
      }
    }
    return accepted;
  }

  Future<int> _pushItems(List<Map<String, dynamic>> items) async {
    final resp = await apiClient.dio.post(
      '/sync/push',
      data: {
        'deviceId': await _getDeviceId(),
        'keyFingerprint': await _keyFingerprintOrEmpty(),
        'items': items,
      },
      options: _syncRequestOptions(),
    );
    final data = _responseData(resp.data);
    return (data['accepted'] as num?)?.toInt() ?? items.length;
  }

  Future<int> _pull() async {
    final since = await getLastSyncMs();
    final rawItems = <dynamic>[];
    int? serverTime;
    var offset = 0;
    while (true) {
      final resp = await apiClient.dio.get(
        '/sync/pull',
        options: Options(
            headers: {'X-Key-Fingerprint': await _keyFingerprintOrEmpty()},
            connectTimeout: const Duration(seconds: 15),
            sendTimeout: const Duration(seconds: 90),
            receiveTimeout: const Duration(seconds: 90)),
        queryParameters: {
          'since': since,
          'limit': 500,
          'offset': offset,
          if (serverTime != null) 'until': serverTime,
        },
      );
      final data = _responseData(resp.data);
      final page = data['items'] as List? ?? [];
      rawItems.addAll(page);
      serverTime ??= (data['serverTime'] as num?)?.toInt();
      if (data['hasMore'] != true || page.isEmpty) break;
      offset += page.length;
    }

    var merged = 0;
    if (rawItems.isNotEmpty) {
      final db = await database.open();
      final now = DateTime.now().millisecondsSinceEpoch;
      var decryptableRows = 0;
      var decryptFailures = 0;

      for (final raw in rawItems) {
        final item = raw as Map<String, dynamic>;
        try {
          final table = item['table'] as String? ?? '';
          final config = _configByTable[table];
          if (config == null) continue;
          final clientId = item['clientId'] as String? ?? '';
          final deleted = item['deleted'] == true;
          if (deleted) {
            if (clientId.isNotEmpty) {
              await db.delete(
                table,
                where: 'client_id = ?',
                whereArgs: [clientId],
              );
              merged++;
            }
            continue;
          }

          decryptableRows++;
          final enc = EncryptedPayload.fromJson(item);
          final version = (item['version'] as num?)?.toInt() ?? 0;
          final plaintext = await cryptoService.decryptToString(
            enc,
            aad: enc.alg == 'aes-256-gcm:v2'
                ? _syncAad(table, clientId, version)
                : null,
          );
          final payload = _decodePayload(table, plaintext, item);
          final effectiveClientId = clientId.isNotEmpty
              ? clientId
              : payload['client_id'] as String? ?? _uuid.v4();
          final clientUpdatedAt = (item['clientUpdatedAt'] as num?)?.toInt() ??
              _asInt(payload['updated_at']) ??
              now;

          final row = await _preparePulledRow(
            table: table,
            payload: payload,
            clientId: effectiveClientId,
            version: (item['version'] as num?)?.toInt() ?? 0,
            clientUpdatedAt: clientUpdatedAt,
            syncAt: now,
          );

          final existing =
              await _findExistingRow(db, config, effectiveClientId);
          if (existing == null) {
            await db.insert(table, row);
            merged++;
            continue;
          }

          final localUpdatedAt = _asInt(existing['updated_at']) ?? 0;
          final localDirty = _asInt(existing['is_dirty']) == 1;
          if (!localDirty || localUpdatedAt <= clientUpdatedAt) {
            await db.update(
              table,
              row..remove('id'),
              where: 'id = ?',
              whereArgs: [existing['id']],
            );
            merged++;
          }
        } catch (e) {
          if (_isDecryptError(e)) {
            decryptFailures++;
            continue;
          }
          // A single corrupt or incompatible row should not break all sync.
          continue;
        }
      }

      if (decryptableRows > 0 && decryptFailures == decryptableRows) {
        throw StateError('数据损坏或密钥错误');
      }

      repository.signalChanged();
    }

    if (serverTime != null) await _saveLastSyncMs(serverTime);
    return merged;
  }

  Options _syncRequestOptions() => Options(
        connectTimeout: const Duration(seconds: 15),
        sendTimeout: const Duration(seconds: 90),
        receiveTimeout: const Duration(seconds: 90),
      );

  Future<Map<String, Object?>> _ensureClientId(
    AppDatabase db,
    _TableConfig config,
    Map<String, Object?> row,
  ) async {
    final existing = row['client_id'] as String?;
    if (existing != null && existing.isNotEmpty) return row;

    final clientId =
        config.profileSingleton ? 'profile-$kLocalUserId' : _uuid.v4();
    final updated = Map<String, Object?>.from(row)..['client_id'] = clientId;
    await db.update(
      config.table,
      {'client_id': clientId},
      where: 'id = ?',
      whereArgs: [row['id']],
    );
    return updated;
  }

  Future<Map<String, Object?>> _buildEncryptedRowPayload(
    String table,
    Map<String, Object?> row,
  ) async {
    final payload = <String, Object?>{
      for (final entry in row.entries)
        if (!_localOnlyColumns.contains(entry.key)) entry.key: entry.value,
    };
    payload['user_id'] = kLocalUserId;

    if (table == 'health_report' || table == 'meal_record') {
      final imagePath = row['image_path'] as String? ?? '';
      final imageBytes = await readReportImage(imagePath);
      if (imageBytes != null) {
        payload['image_base64'] = base64Encode(imageBytes);
        payload['image_ext'] = _imageExtension(imagePath);
      }
    }

    return payload;
  }

  Future<Map<String, Object?>> _preparePulledRow({
    required String table,
    required Map<String, dynamic> payload,
    required String clientId,
    required int version,
    required int clientUpdatedAt,
    required int syncAt,
  }) async {
    final row = Map<String, Object?>.from(payload)
      ..remove('id')
      ..remove('image_base64')
      ..remove('image_ext')
      ..['user_id'] = kLocalUserId
      ..['client_id'] = clientId
      ..['version'] = _asInt(payload['version']) ?? version
      ..['is_dirty'] = 0
      ..['sync_at'] = syncAt
      ..['created_at'] = _asInt(payload['created_at']) ?? clientUpdatedAt
      ..['updated_at'] = _asInt(payload['updated_at']) ?? clientUpdatedAt;

    switch (table) {
      case 'user_profile':
        row.addAll({
          'nickname': row['nickname'] ?? '',
          'gender': row['gender'] ?? 'unknown',
          'birth_year': _asInt(row['birth_year']) ?? 0,
          'height_cm': _asDouble(row['height_cm']),
          'weight_kg': _asDouble(row['weight_kg']),
          'medical_history': row['medical_history'] ?? '',
          'medications': row['medications'] ?? '',
          'goal': row['goal'] ?? 'maintain',
          'exercise_base': row['exercise_base'] ?? 'none',
          'diet_preference': row['diet_preference'] ?? 'normal',
        });
      case 'health_indicator':
        row.addAll({
          'type': row['type'] ?? 'weight',
          'payload_json': row['payload_json'] ?? '{}',
          'source': row['source'] ?? 'manual',
          'measured_at': _asInt(row['measured_at']) ?? clientUpdatedAt,
        });
      case 'plan':
        row.addAll({
          'type': row['type'] ?? 'meal',
          'plan_date': _asInt(row['plan_date']) ?? clientUpdatedAt,
          'payload_json': row['payload_json'] ?? '{}',
          'ai_provider': row['ai_provider'] ?? '',
          'ai_model': row['ai_model'] ?? '',
        });
      case 'clock_record':
        row.addAll({
          'type': row['type'] ?? 'meal',
          'status': row['status'] ?? 'done',
          'clock_at': _asInt(row['clock_at']) ?? clientUpdatedAt,
          'note': row['note'] ?? '',
          'photo_path': row['photo_path'] ?? '',
        });
      case 'reminder':
        row.addAll({
          'type': row['type'] ?? 'meal',
          'remind_at': _asInt(row['remind_at']) ?? clientUpdatedAt,
          'payload_json': row['payload_json'] ?? '{}',
          'channel': row['channel'] ?? 'local',
          'status': row['status'] ?? 'pending',
        });
      case 'health_report':
        row.addAll({
          'image_path': await _restoreReportImage(payload, clientId),
          'report_time': _asInt(row['report_time']) ?? clientUpdatedAt,
          'summary': row['summary'] ?? '',
          'raw_text': row['raw_text'] ?? '',
          'structured_json': row['structured_json'] ?? '{}',
          'provider': row['provider'] ?? '',
        });
      case 'meal_record':
        row.addAll({
          'name': row['name'] ?? '',
          'meal_type': row['meal_type'] ?? 'lunch',
          'eaten_at': _asInt(row['eaten_at']) ?? clientUpdatedAt,
          'image_path': await _restoreReportImage(payload, clientId),
          'total_calories': _asDouble(row['total_calories']),
          'protein_g': _asDouble(row['protein_g']),
          'carbs_g': _asDouble(row['carbs_g']),
          'fat_g': _asDouble(row['fat_g']),
          'health_score': _asDouble(row['health_score']),
          'glycemic_load': _asDouble(row['glycemic_load']),
          'foods_json': row['foods_json'] ?? '[]',
          'nutrition_json': row['nutrition_json'] ?? '{}',
        });
    }
    return row;
  }

  Future<String> _restoreReportImage(
    Map<String, dynamic> payload,
    String clientId,
  ) async {
    final imageBase64 = payload['image_base64'] as String?;
    if (imageBase64 == null || imageBase64.isEmpty) {
      return payload['image_path'] as String? ?? '';
    }

    final ext = (payload['image_ext'] as String?)?.isNotEmpty == true
        ? payload['image_ext'] as String
        : '.jpg';
    return restoreReportImage(base64Decode(imageBase64), clientId, ext);
  }

  String _imageExtension(String imagePath) {
    if (imagePath.startsWith('data:image/png')) return '.png';
    if (imagePath.startsWith('data:image/webp')) return '.webp';
    final match = RegExp(r'\.[a-zA-Z0-9]+$').firstMatch(imagePath);
    return match?.group(0) ?? '.jpg';
  }

  Map<String, dynamic> _decodePayload(
    String table,
    String plaintext,
    Map<String, dynamic> item,
  ) {
    final decoded = jsonDecode(plaintext);
    if (decoded is Map) {
      final mapped = decoded.map((key, value) => MapEntry('$key', value));
      if (table == 'health_indicator' && !mapped.containsKey('payload_json')) {
        final meta = item['meta'] as Map<String, dynamic>? ?? {};
        return {
          'type': meta['type'] ?? mapped['type'] ?? 'weight',
          'payload_json': jsonEncode(mapped),
          'source': meta['source'] ?? 'cloud',
          'measured_at': meta['measured_at'] ?? item['clientUpdatedAt'],
        };
      }
      return mapped;
    }

    // Backward compatibility: older health sync encrypted only payload_json.
    if (table == 'health_indicator') {
      final meta = item['meta'] as Map<String, dynamic>? ?? {};
      return {
        'type': meta['type'] ?? 'weight',
        'payload_json': plaintext,
        'source': meta['source'] ?? 'cloud',
        'measured_at': meta['measured_at'] ?? item['clientUpdatedAt'],
      };
    }
    return {};
  }

  Future<Map<String, Object?>?> _findExistingRow(
    AppDatabase db,
    _TableConfig config,
    String clientId,
  ) async {
    final rows = await db.query(
      config.table,
      where: 'client_id = ?',
      whereArgs: [clientId],
      limit: 1,
    );
    if (rows.isNotEmpty) return rows.first;

    if (config.profileSingleton) {
      final profileRows = await db.query(
        config.table,
        where: 'user_id = ?',
        whereArgs: [kLocalUserId],
        limit: 1,
      );
      if (profileRows.isNotEmpty) return profileRows.first;
    }
    return null;
  }

  Map<String, Object?> _buildMeta(
    _TableConfig config,
    Map<String, Object?> row,
  ) {
    return {
      for (final key in config.metaKeys)
        if (row[key] != null) key: row[key],
    };
  }

  List<int> _syncAad(String table, String clientId, int version) {
    final userId = UserSession.instance.userId ?? '';
    return utf8.encode('hrp-sync:v2:$userId:$table:$clientId:$version');
  }

  Map<String, dynamic> _responseData(Object? body) {
    if (body is Map) {
      final code = body['code'];
      if (code != null && code != 0) {
        throw StateError(
          body['message']?.toString() ?? body['msg']?.toString() ?? '云同步请求失败',
        );
      }
      if (body['data'] is Map) {
        return Map<String, dynamic>.from(body['data'] as Map);
      }
      return Map<String, dynamic>.from(body);
    }
    return {};
  }

  bool _isRetryable(Object? error) {
    if (error is DioException) {
      final status = error.response?.statusCode;
      if (status == 503 || status == 502 || status == 504) return true;
      final body = error.response?.data;
      if (body is Map) {
        final code = (body['code'] as num?)?.toInt() ?? 0;
        if (code == 50001 || code == 50301) return true;
      }
      return error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.connectionError;
    }
    final text = '$error';
    return text.contains('系统繁忙') ||
        text.contains('503') ||
        text.contains('50001');
  }

  String _friendlySyncError(Object? error) {
    if (error is DioException) {
      final status = error.response?.statusCode;
      final body = error.response?.data;
      if (status == 503 ||
          (body is Map && ((body['code'] as num?)?.toInt() == 50001))) {
        return '系统繁忙，请稍后再试';
      }
      if (body is Map) {
        final code = (body['code'] as num?)?.toInt() ?? 0;
        final message = (body['message'] ?? body['msg'])?.toString();
        if (code == 40301) return message ?? '云同步功能需要开通会员，免费版数据仅保存在本地设备';
        if (code == 50301) return '系统繁忙，请稍后再试';
        if (message != null && message.isNotEmpty) return message;
      }
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.connectionError) {
        return '网络异常，请检查网络后重试';
      }
      return error.message ?? '网络异常，请检查网络后重试';
    }
    if (_isDecryptError(error)) {
      return '密钥异常，请检查主密钥状态';
    }
    final text = '$error';
    if (text.contains('系统繁忙') ||
        text.contains('50001') ||
        text.contains('503')) {
      return '系统繁忙，请稍后再试';
    }
    if (text.contains('UMK') || text.contains('主密钥')) {
      return '密钥异常，请检查主密钥状态';
    }
    return text.isEmpty ? '云同步请求失败' : text;
  }

  bool _isDecryptError(Object? error) {
    final text = '$error';
    return text.contains('SecretBox') ||
        text.contains('authentication') ||
        text.contains('mac') ||
        text.contains('数据损坏') ||
        text.contains('密钥错误') ||
        text.contains('Invalid argument(s): Invalid or corrupted pad block');
  }

  static const _localOnlyColumns = {
    'id',
    'is_dirty',
    'sync_at',
  };

  int? _asInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value');
  }

  double _asDouble(Object? value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? 0;
  }
}
