import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../crypto/crypto_service.dart';
import '../data/health_models.dart';
import '../data/health_repository.dart';
import '../network/api_client.dart';
import '../storage/app_database.dart';
import 'health_sync_bridge.dart';

class SyncResult {
  const SyncResult({required this.pushed, required this.pulled, this.error});

  final int pushed;
  final int pulled;
  final String? error;

  bool get hasError => error != null;
}

class _TableConfig {
  const _TableConfig({required this.table, required this.metaKeys});
  final String table;
  final List<String> metaKeys;
}

/// 客户端加密增量同步服务。
///
/// push：将本地 is_dirty=1 的记录加密后上传；成功后清除 dirty 标记。
/// pull：增量拉取服务端新数据，解密后按 last-write-wins 合并到本地。
class SyncService {
  SyncService({
    required this.apiClient,
    required this.cryptoService,
    required this.database,
    required this.repository,
    HealthSyncBridge? healthSyncBridge,
  }) : healthSyncBridge = healthSyncBridge ?? HealthSyncBridge();

  final ApiClient apiClient;
  final CryptoService cryptoService;
  final AppDatabase database;
  final HealthRepository repository;
  final HealthSyncBridge healthSyncBridge;

  static const String _kLastSyncMs = 'sync_last_ms';
  static const String _kSyncEnabled = 'sync_enabled';

  static const _tables = [
    _TableConfig(
      table: 'health_indicator',
      metaKeys: ['type', 'measured_at', 'source'],
    ),
  ];

  Future<bool> isSyncEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kSyncEnabled) ?? false;
  }

  Future<void> setSyncEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSyncEnabled, enabled);
  }

  Future<int> getLastSyncMs() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kLastSyncMs) ?? 0;
  }

  Future<void> _saveLastSyncMs(int ms) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kLastSyncMs, ms);
  }

  Future<SyncResult> sync() async {
    try {
      final pushed = await _push();
      final pulled = await _pull();
      return SyncResult(pushed: pushed, pulled: pulled);
    } on DioException catch (e) {
      final body = e.response?.data;
      final msg = body is Map
          ? (body['message'] as String? ?? e.message ?? '网络错误')
          : (e.message ?? '网络错误');
      return SyncResult(pushed: 0, pulled: 0, error: msg);
    } catch (e) {
      return SyncResult(pushed: 0, pulled: 0, error: '$e');
    }
  }

  Future<SyncResult> syncSystemHealth() async {
    try {
      final available = await healthSyncBridge.isAvailable();
      if (!available) {
        return const SyncResult(
          pushed: 0,
          pulled: 0,
          error: '当前系统不支持健康数据同步，请安装或启用 Health Connect / HealthKit',
        );
      }

      final access = await healthSyncBridge.requestAccess();
      if (!access.anyGranted) {
        return const SyncResult(pushed: 0, pulled: 0, error: '未获得任何健康数据读取权限');
      }

      final snapshot = await healthSyncBridge.sync();
      final inserted = await repository.ingestSystemHealthSnapshot(
        steps: snapshot.steps,
        heartRateBpm: snapshot.heartRateBpm,
        sleepHours: snapshot.sleepHours,
        recordedAt: snapshot.recordedAt,
      );
      if (inserted == 0) {
        return const SyncResult(
          pushed: 0,
          pulled: 0,
          error: '已获得健康数据权限，但暂未读取到步数、心率或睡眠数据',
        );
      }
      return SyncResult(pushed: inserted, pulled: 0);
    } catch (e) {
      return SyncResult(pushed: 0, pulled: 0, error: '$e');
    }
  }

  Future<int> _push() async {
    final db = await database.open();
    var totalAccepted = 0;

    for (final config in _tables) {
      final dirtyRows = await db.query(
        config.table,
        where: 'is_dirty = 1 AND client_id IS NOT NULL',
      );
      if (dirtyRows.isEmpty) continue;

      final items = <Map<String, dynamic>>[];
      for (final row in dirtyRows) {
        final rawPayload = row['payload_json'] as String? ?? '{}';
        final enc = await cryptoService.encryptString(rawPayload);

        final meta = <String, dynamic>{
          for (final k in config.metaKeys)
            if (row[k] != null) k: row[k],
        };

        items.add({
          'table': config.table,
          'clientId': row['client_id'],
          'version': row['version'] ?? 0,
          'clientUpdatedAt': row['updated_at'],
          ...enc.toJson(), // cipher, iv, tag, alg
          'meta': meta,
        });
      }

      final resp =
          await apiClient.dio.post('/sync/push', data: {'items': items});
      final accepted =
          (resp.data?['data']?['accepted'] as num?)?.toInt() ?? items.length;
      totalAccepted += accepted;

      final now = DateTime.now().millisecondsSinceEpoch;
      for (final row in dirtyRows) {
        await db.update(
          config.table,
          {'is_dirty': 0, 'sync_at': now},
          where: 'client_id = ?',
          whereArgs: [row['client_id']],
        );
      }
    }

    return totalAccepted;
  }

  Future<int> _pull() async {
    final since = await getLastSyncMs();
    final resp = await apiClient.dio.get(
      '/sync/pull',
      queryParameters: {'since': since, 'limit': 200},
    );

    final data = resp.data?['data'] as Map<String, dynamic>? ?? {};
    final rawItems = data['items'] as List? ?? [];
    final serverTime = (data['serverTime'] as num?)?.toInt();

    var merged = 0;
    if (rawItems.isNotEmpty) {
      final db = await database.open();
      final now = DateTime.now().millisecondsSinceEpoch;

      for (final raw in rawItems) {
        final item = raw as Map<String, dynamic>;
        try {
          final enc = EncryptedPayload.fromJson(item);
          final plaintext = await cryptoService.decryptToString(enc);

          final table = item['table'] as String;
          final clientId = item['clientId'] as String;
          final clientUpdatedAt = (item['clientUpdatedAt'] as num).toInt();
          final meta = item['meta'] as Map<String, dynamic>? ?? {};

          final existing = await db.query(
            table,
            where: 'client_id = ?',
            whereArgs: [clientId],
            limit: 1,
          );

          if (existing.isEmpty) {
            await db.insert(table, {
              'client_id': clientId,
              'user_id': kLocalUserId,
              'payload_json': plaintext,
              'version': (item['version'] as num?)?.toInt() ?? 0,
              'is_dirty': 0,
              'sync_at': now,
              'created_at': clientUpdatedAt,
              'updated_at': clientUpdatedAt,
              ...meta,
            });
            merged++;
          } else {
            final localUpdatedAt =
                (existing.first['updated_at'] as num?)?.toInt() ?? 0;
            if (localUpdatedAt <= clientUpdatedAt) {
              // 服务端版本更新，覆盖本地；否则保留本地，下次 push 时会上传
              await db.update(
                table,
                {
                  'payload_json': plaintext,
                  'version': (item['version'] as num?)?.toInt() ?? 0,
                  'is_dirty': 0,
                  'sync_at': now,
                  'updated_at': clientUpdatedAt,
                },
                where: 'client_id = ?',
                whereArgs: [clientId],
              );
              merged++;
            }
          }
        } catch (_) {
          // 单条解密失败不中断整体同步
          continue;
        }
      }

      repository.signalChanged();
    }

    if (serverTime != null) await _saveLastSyncMs(serverTime);
    return merged;
  }
}
