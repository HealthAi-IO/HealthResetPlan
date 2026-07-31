import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

import '../network/online_data_api.dart';

abstract class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = _SqfliteAppDatabase();

  Future<AppDatabase> open();
  Future<void> close();

  Future<List<Map<String, Object?>>> query(
    String table, {
    String? where,
    List<Object?>? whereArgs,
    String? orderBy,
    int? limit,
  });

  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    bool replace = false,
  });

  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
  });

  Future<int> delete(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  });

  Future<int> count(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  });

  Future<T> transaction<T>(Future<T> Function(AppDatabase txn) action);

  String get activeSpace => 'local';

  Future<void> switchSpace(String space) async {}

  Future<bool> hasDataInSpace(String space) async => false;

  Future<void> moveSpace(String from, String to) async {}

  Future<void> bindOnline(OnlineDataApi api) async {
    throw UnsupportedError('当前数据库不支持在线数据');
  }

  Future<void> unbindOnline() async {}
}

class _SqfliteAppDatabase extends AppDatabase {
  _SqfliteAppDatabase() : super._();

  sqflite.Database? _db;
  String _activeSpace = 'online';
  OnlineDataApi? _onlineApi;
  int _onlineVersion = 0;
  bool _persisting = false;
  static const int _schemaVersion = 11;
  static const _scopedTables = [
    'user_profile',
    'health_indicator',
    'plan',
    'clock_record',
    'reminder',
    'sync_queue',
    'health_report',
    'meal_record',
    'ai_session',
    'ai_message',
  ];

  @override
  String get activeSpace => _activeSpace;

  @override
  Future<void> switchSpace(String space) async {
    _activeSpace = space;
  }

  @override
  Future<bool> hasDataInSpace(String space) async {
    final db = await _ensureDb();
    for (final table in _scopedTables) {
      final rows = await db.query(
        table,
        columns: const ['id'],
        where: 'space_id = ?',
        whereArgs: [space],
        limit: 1,
      );
      if (rows.isNotEmpty) return true;
    }
    return false;
  }

  @override
  Future<void> moveSpace(String from, String to) async {
    if (from == to) return;
    final db = await _ensureDb();
    await db.transaction((txn) async {
      for (final table in _scopedTables) {
        await txn.update(
          table,
          {'space_id': to},
          where: 'space_id = ?',
          whereArgs: [from],
        );
      }
    });
  }

  Future<sqflite.Database> _ensureDb() async {
    if (_db != null) return _db!;

    if (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      ffi.sqfliteFfiInit();
      sqflite.databaseFactory = ffi.databaseFactoryFfi;
    }

    _db = await sqflite.databaseFactory.openDatabase(
      sqflite.inMemoryDatabasePath,
      options: sqflite.OpenDatabaseOptions(
        version: _schemaVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON;');
          await db.rawQuery('PRAGMA journal_mode = WAL;');
        },
      ),
    );
    return _db!;
  }

  @override
  Future<AppDatabase> open() async {
    await _ensureDb();
    return this;
  }

  @override
  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    String? where,
    List<Object?>? whereArgs,
    String? orderBy,
    int? limit,
  }) async {
    final db = await _ensureDb();
    final scopedWhere = _scopeWhere(where, whereArgs);
    return db.query(
      table,
      where: scopedWhere.$1,
      whereArgs: scopedWhere.$2,
      orderBy: orderBy,
      limit: limit,
    );
  }

  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    bool replace = false,
  }) async {
    final db = await _ensureDb();
    final id = await db.insert(
      table,
      {...values, 'space_id': _activeSpace},
      conflictAlgorithm: replace ? sqflite.ConflictAlgorithm.replace : null,
    );
    await _persistOnline();
    return id;
  }

  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    final db = await _ensureDb();
    final scopedWhere = _scopeWhere(where, whereArgs);
    final count = await db.update(
      table,
      values,
      where: scopedWhere.$1,
      whereArgs: scopedWhere.$2,
    );
    if (count > 0) await _persistOnline();
    return count;
  }

  @override
  Future<int> delete(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    final db = await _ensureDb();
    final scopedWhere = _scopeWhere(where, whereArgs);
    final count = await db.delete(
      table,
      where: scopedWhere.$1,
      whereArgs: scopedWhere.$2,
    );
    if (count > 0) await _persistOnline();
    return count;
  }

  @override
  Future<int> count(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    final rows = await query(
      table,
      where: where,
      whereArgs: whereArgs,
    );
    return rows.length;
  }

  @override
  Future<T> transaction<T>(Future<T> Function(AppDatabase txn) action) async {
    final db = await _ensureDb();
    final result = await db.transaction((txn) async {
      return action(_SqfliteTransactionAppDatabase(txn, _activeSpace));
    });
    await _persistOnline();
    return result;
  }

  @override
  Future<void> bindOnline(OnlineDataApi api) async {
    _onlineApi = api;
    await _loadOnline();
  }

  @override
  Future<void> unbindOnline() async {
    _onlineApi = null;
    _onlineVersion = 0;
    await _clearBusinessTables();
  }

  Future<void> _loadOnline() async {
    final api = _onlineApi;
    if (api == null) return;
    final space = _activeSpace;
    final snapshot = await api.load();
    if (!identical(_onlineApi, api) || _activeSpace != space) return;
    final db = await _ensureDb();
    _persisting = true;
    try {
      await db.transaction((txn) async {
        for (final table in _onlineTables) {
          await txn.delete(table);
          for (final row in snapshot.tables[table] ?? const []) {
            await txn.insert(
              table,
              {...row, 'space_id': space},
              conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
            );
          }
        }
      });
      _onlineVersion = snapshot.version;
    } finally {
      _persisting = false;
    }
  }

  Future<void> _persistOnline() async {
    final api = _onlineApi;
    if (api == null || _persisting) return;
    _persisting = true;
    try {
      final db = await _ensureDb();
      final tables = <String, List<Map<String, Object?>>>{};
      for (final table in _onlineTables) {
        final rows = await db.query(
          table,
          where: 'space_id = ?',
          whereArgs: [_activeSpace],
        );
        tables[table] = rows
            .map((row) => Map<String, Object?>.from(row)..remove('space_id'))
            .toList();
      }
      final saved = await api.save(_onlineVersion, tables);
      _onlineVersion = saved.version;
    } catch (_) {
      await _loadOnline();
      rethrow;
    } finally {
      _persisting = false;
    }
  }

  Future<void> _clearBusinessTables() async {
    final db = await _ensureDb();
    await db.transaction((txn) async {
      for (final table in _onlineTables) {
        await txn.delete(table);
      }
    });
  }

  static const _onlineTables = [
    'user_profile',
    'health_indicator',
    'plan',
    'clock_record',
    'reminder',
    'health_report',
    'meal_record',
    'ai_session',
    'ai_message',
  ];

  Future<void> _onCreate(sqflite.Database db, int version) async {
    await db.execute(_ddlUserProfile);
    await db.execute(_ddlHealthIndicator);
    await db.execute(_ddlPlan);
    await db.execute(_ddlClockRecord);
    await db.execute(_ddlReminder);
    await db.execute(_ddlSyncQueue);
    await db.execute(_ddlAiSession);
    await db.execute(_ddlAiMessage);
    await db.execute(_idxAiMessageSession);
    await db.execute(_ddlHealthReport);
    await db.execute(_ddlMealRecord);
    await _ensureSpaceColumns(db);
  }

  Future<void> _onUpgrade(
      sqflite.Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // v2：为可同步表加 client_id（UUID，云端幂等键）和 sync_at（上次成功同步时间）
      for (final t in [
        'health_indicator',
        'plan',
        'clock_record',
        'reminder'
      ]) {
        await db.execute('ALTER TABLE $t ADD COLUMN client_id TEXT');
        await db.execute(
            'ALTER TABLE $t ADD COLUMN sync_at INTEGER NOT NULL DEFAULT 0');
      }
    }
    if (oldVersion < 3) {
      // v3：user_profile 新增目标、运动基础、饮食偏好字段
      await db.execute(
          "ALTER TABLE user_profile ADD COLUMN goal TEXT NOT NULL DEFAULT 'maintain'");
      await db.execute(
          "ALTER TABLE user_profile ADD COLUMN exercise_base TEXT NOT NULL DEFAULT 'none'");
      await db.execute(
          "ALTER TABLE user_profile ADD COLUMN diet_preference TEXT NOT NULL DEFAULT 'normal'");
    }
    if (oldVersion < 4) {
      // v4：AI 对话历史持久化
      await db.execute(_ddlAiSession);
      await db.execute(_ddlAiMessage);
      await db.execute(_idxAiMessageSession);
    }
    if (oldVersion < 7) {
      await db.execute(_ddlHealthReport);
    }
    if (oldVersion < 8) {
      // v8：补齐旧版本数据库的元数据列。
      // 这里用幂等检查避免重复 ALTER 导致升级失败。
      await _addColumnIfMissing(db, 'user_profile', 'client_id', 'TEXT');
      await _addColumnIfMissing(
          db, 'user_profile', 'sync_at', 'INTEGER NOT NULL DEFAULT 0');

      for (final t in ['clock_record', 'reminder']) {
        await _addColumnIfMissing(db, t, 'client_id', 'TEXT');
        await _addColumnIfMissing(
            db, t, 'sync_at', 'INTEGER NOT NULL DEFAULT 0');
      }

      await _addColumnIfMissing(
          db, 'health_report', 'version', 'INTEGER NOT NULL DEFAULT 0');
      await _addColumnIfMissing(
          db, 'health_report', 'is_dirty', 'INTEGER NOT NULL DEFAULT 1');
      await _addColumnIfMissing(
          db, 'health_report', 'sync_at', 'INTEGER NOT NULL DEFAULT 0');
    }
    if (oldVersion < 9) {
      await db.execute(_ddlMealRecord);
    }
    if (oldVersion < 10) {
      await _addColumnIfMissing(db, 'ai_session', 'session_uuid', 'TEXT');
      await _addColumnIfMissing(
          db, 'ai_session', 'version', 'INTEGER NOT NULL DEFAULT 0');
      await _addColumnIfMissing(
          db, 'ai_session', 'is_dirty', 'INTEGER NOT NULL DEFAULT 1');
      await _addColumnIfMissing(
          db, 'ai_session', 'sync_at', 'INTEGER NOT NULL DEFAULT 0');
      await _addColumnIfMissing(db, 'ai_message', 'message_uuid', 'TEXT');
      await _addColumnIfMissing(db, 'ai_message', 'session_uuid', 'TEXT');
      await _addColumnIfMissing(
          db, 'ai_message', 'updated_at', 'INTEGER NOT NULL DEFAULT 0');
      await _addColumnIfMissing(
          db, 'ai_message', 'version', 'INTEGER NOT NULL DEFAULT 0');
      await _addColumnIfMissing(
          db, 'ai_message', 'is_dirty', 'INTEGER NOT NULL DEFAULT 1');
      await _addColumnIfMissing(
          db, 'ai_message', 'sync_at', 'INTEGER NOT NULL DEFAULT 0');
    }
    if (oldVersion < 11) {
      await _ensureSpaceColumns(db);
    }
  }

  Future<void> _ensureSpaceColumns(sqflite.Database db) async {
    for (final table in _scopedTables) {
      await _addColumnIfMissing(
        db,
        table,
        'space_id',
        "TEXT NOT NULL DEFAULT 'local'",
      );
    }
  }

  (String, List<Object?>) _scopeWhere(
    String? where, [
    List<Object?>? whereArgs,
  ]) {
    if (where == null || where.trim().isEmpty) {
      return ('space_id = ?', [_activeSpace]);
    }
    return ('($where) AND space_id = ?', [...?whereArgs, _activeSpace]);
  }

  Future<void> _addColumnIfMissing(
    sqflite.Database db,
    String table,
    String column,
    String definition,
  ) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    final exists = columns.any((row) => row['name'] == column);
    if (!exists) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
    }
  }
}

class _SqfliteTransactionAppDatabase extends AppDatabase {
  _SqfliteTransactionAppDatabase(this._txn, this._activeSpace) : super._();

  final sqflite.Transaction _txn;
  final String _activeSpace;

  @override
  String get activeSpace => _activeSpace;

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
  }) {
    final scopedWhere = _scopeWhere(where, whereArgs);
    return _txn.query(
      table,
      where: scopedWhere.$1,
      whereArgs: scopedWhere.$2,
      orderBy: orderBy,
      limit: limit,
    );
  }

  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    bool replace = false,
  }) {
    return _txn.insert(
      table,
      {...values, 'space_id': _activeSpace},
      conflictAlgorithm: replace ? sqflite.ConflictAlgorithm.replace : null,
    );
  }

  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
  }) {
    final scopedWhere = _scopeWhere(where, whereArgs);
    return _txn.update(
      table,
      values,
      where: scopedWhere.$1,
      whereArgs: scopedWhere.$2,
    );
  }

  @override
  Future<int> delete(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) {
    final scopedWhere = _scopeWhere(where, whereArgs);
    return _txn.delete(
      table,
      where: scopedWhere.$1,
      whereArgs: scopedWhere.$2,
    );
  }

  @override
  Future<int> count(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    final rows = await query(
      table,
      where: where,
      whereArgs: whereArgs,
    );
    return rows.length;
  }

  @override
  Future<T> transaction<T>(Future<T> Function(AppDatabase txn) action) {
    return action(this);
  }

  @override
  Future<void> bindOnline(OnlineDataApi api) async {
    throw UnsupportedError('事务中不能切换账号');
  }

  @override
  Future<void> unbindOnline() async {
    throw UnsupportedError('事务中不能切换账号');
  }

  (String, List<Object?>) _scopeWhere(
    String? where,
    List<Object?>? whereArgs,
  ) {
    if (where == null || where.trim().isEmpty) {
      return ('space_id = ?', [_activeSpace]);
    }
    return ('($where) AND space_id = ?', [...?whereArgs, _activeSpace]);
  }
}

// ---- DDL ----

const String _ddlUserProfile = '''
    CREATE TABLE IF NOT EXISTS user_profile (
      id              INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id         TEXT    NOT NULL,
      nickname        TEXT    NOT NULL DEFAULT '',
      gender          TEXT    NOT NULL DEFAULT '',
      birth_year      INTEGER NOT NULL DEFAULT 0,
      height_cm       REAL    NOT NULL DEFAULT 0,
      weight_kg       REAL    NOT NULL DEFAULT 0,
      medical_history TEXT    NOT NULL DEFAULT '',
      medications     TEXT    NOT NULL DEFAULT '',
      created_at      INTEGER NOT NULL,
      updated_at      INTEGER NOT NULL,
      client_id       TEXT,
      goal            TEXT    NOT NULL DEFAULT 'maintain',
      exercise_base   TEXT    NOT NULL DEFAULT 'none',
      diet_preference TEXT    NOT NULL DEFAULT 'normal',
      version         INTEGER NOT NULL DEFAULT 0,
      is_dirty        INTEGER NOT NULL DEFAULT 1,
      sync_at         INTEGER NOT NULL DEFAULT 0
    );
''';

const String _ddlHealthIndicator = '''
    CREATE TABLE IF NOT EXISTS health_indicator (
      id           INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id      TEXT    NOT NULL,
      client_id    TEXT,
      type         TEXT    NOT NULL,
      payload_json TEXT    NOT NULL,
      source       TEXT    NOT NULL DEFAULT 'manual',
      measured_at  INTEGER NOT NULL,
      created_at   INTEGER NOT NULL,
      updated_at   INTEGER NOT NULL,
      version      INTEGER NOT NULL DEFAULT 0,
      is_dirty     INTEGER NOT NULL DEFAULT 1,
      sync_at      INTEGER NOT NULL DEFAULT 0
    );
''';

const String _ddlPlan = '''
    CREATE TABLE IF NOT EXISTS plan (
      id           INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id      TEXT    NOT NULL,
      client_id    TEXT,
      type         TEXT    NOT NULL,
      plan_date    INTEGER NOT NULL,
      payload_json TEXT    NOT NULL,
      ai_provider  TEXT    NOT NULL DEFAULT '',
      ai_model     TEXT    NOT NULL DEFAULT '',
      created_at   INTEGER NOT NULL,
      updated_at   INTEGER NOT NULL,
      version      INTEGER NOT NULL DEFAULT 0,
      is_dirty     INTEGER NOT NULL DEFAULT 1,
      sync_at      INTEGER NOT NULL DEFAULT 0
    );
''';

const String _ddlClockRecord = '''
    CREATE TABLE IF NOT EXISTS clock_record (
      id          INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id     TEXT    NOT NULL,
      client_id   TEXT,
      type        TEXT    NOT NULL,
      status      TEXT    NOT NULL DEFAULT 'done',
      clock_at    INTEGER NOT NULL,
      note        TEXT    NOT NULL DEFAULT '',
      photo_path  TEXT    NOT NULL DEFAULT '',
      created_at  INTEGER NOT NULL,
      updated_at  INTEGER NOT NULL,
      version     INTEGER NOT NULL DEFAULT 0,
      is_dirty    INTEGER NOT NULL DEFAULT 1,
      sync_at     INTEGER NOT NULL DEFAULT 0
    );
''';

const String _ddlReminder = '''
    CREATE TABLE IF NOT EXISTS reminder (
      id           INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id      TEXT    NOT NULL,
      client_id    TEXT,
      type         TEXT    NOT NULL,
      remind_at    INTEGER NOT NULL,
      payload_json TEXT    NOT NULL DEFAULT '',
      channel      TEXT    NOT NULL DEFAULT 'local',
      status       TEXT    NOT NULL DEFAULT 'pending',
      created_at   INTEGER NOT NULL,
      updated_at   INTEGER NOT NULL,
      version      INTEGER NOT NULL DEFAULT 0,
      is_dirty     INTEGER NOT NULL DEFAULT 1,
      sync_at      INTEGER NOT NULL DEFAULT 0
    );
''';

/// 待同步上传队列：每条记录由模块写入，sync 服务统一加密并上传。
const String _ddlSyncQueue = '''
    CREATE TABLE IF NOT EXISTS sync_queue (
      id            INTEGER PRIMARY KEY AUTOINCREMENT,
      table_name    TEXT    NOT NULL,
      row_id        INTEGER NOT NULL,
      op            TEXT    NOT NULL,
      payload_json  TEXT    NOT NULL DEFAULT '',
      retry         INTEGER NOT NULL DEFAULT 0,
      created_at    INTEGER NOT NULL,
      updated_at    INTEGER NOT NULL
    );
''';

/// AI 对话会话：一个用户可以有多个独立会话。
const String _ddlAiSession = '''
    CREATE TABLE IF NOT EXISTS ai_session (
      id            INTEGER PRIMARY KEY AUTOINCREMENT,
      title         TEXT    NOT NULL DEFAULT '新对话',
      provider      TEXT    NOT NULL DEFAULT 'deepseek',
      message_count INTEGER NOT NULL DEFAULT 0,
      created_at    INTEGER NOT NULL,
      updated_at    INTEGER NOT NULL,
      session_uuid  TEXT,
      version       INTEGER NOT NULL DEFAULT 0,
      is_dirty      INTEGER NOT NULL DEFAULT 1,
      sync_at       INTEGER NOT NULL DEFAULT 0
    );
''';

/// AI 对话消息：归属于某个 session_id。
const String _ddlAiMessage = '''
    CREATE TABLE IF NOT EXISTS ai_message (
      id          INTEGER PRIMARY KEY AUTOINCREMENT,
      session_id  INTEGER NOT NULL,
      role        TEXT    NOT NULL,
      content     TEXT    NOT NULL DEFAULT '',
      provider    TEXT    NOT NULL DEFAULT '',
      is_error    INTEGER NOT NULL DEFAULT 0,
      created_at  INTEGER NOT NULL,
      updated_at  INTEGER NOT NULL,
      message_uuid TEXT,
      session_uuid TEXT,
      version     INTEGER NOT NULL DEFAULT 0,
      is_dirty    INTEGER NOT NULL DEFAULT 1,
      sync_at     INTEGER NOT NULL DEFAULT 0
    );
''';

/// 加速按会话查询
const String _idxAiMessageSession = '''
    CREATE INDEX IF NOT EXISTS idx_ai_message_session
        ON ai_message(session_id, id);
''';

const String _ddlHealthReport = '''
    CREATE TABLE IF NOT EXISTS health_report (
      id              INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id         TEXT    NOT NULL,
      client_id       TEXT    NOT NULL,
      image_path      TEXT    NOT NULL DEFAULT '',
      report_time     INTEGER NOT NULL,
      summary         TEXT    NOT NULL DEFAULT '',
      raw_text        TEXT    NOT NULL DEFAULT '',
      structured_json TEXT    NOT NULL DEFAULT '{}',
      provider        TEXT    NOT NULL DEFAULT '',
      created_at      INTEGER NOT NULL,
      updated_at      INTEGER NOT NULL,
      version         INTEGER NOT NULL DEFAULT 0,
      is_dirty        INTEGER NOT NULL DEFAULT 1,
      sync_at         INTEGER NOT NULL DEFAULT 0
    );
''';

const String _ddlMealRecord = '''
    CREATE TABLE IF NOT EXISTS meal_record (
      id              INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id         TEXT    NOT NULL,
      client_id       TEXT    NOT NULL,
      name            TEXT    NOT NULL DEFAULT '',
      meal_type       TEXT    NOT NULL DEFAULT 'lunch',
      eaten_at        INTEGER NOT NULL,
      image_path      TEXT    NOT NULL DEFAULT '',
      total_calories  REAL    NOT NULL DEFAULT 0,
      protein_g       REAL    NOT NULL DEFAULT 0,
      carbs_g         REAL    NOT NULL DEFAULT 0,
      fat_g           REAL    NOT NULL DEFAULT 0,
      health_score    REAL    NOT NULL DEFAULT 0,
      glycemic_load   REAL    NOT NULL DEFAULT 0,
      foods_json      TEXT    NOT NULL DEFAULT '[]',
      nutrition_json  TEXT    NOT NULL DEFAULT '{}',
      created_at      INTEGER NOT NULL,
      updated_at      INTEGER NOT NULL,
      version         INTEGER NOT NULL DEFAULT 0,
      is_dirty        INTEGER NOT NULL DEFAULT 1,
      sync_at         INTEGER NOT NULL DEFAULT 0
    );
''';
