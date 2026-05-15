import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

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
}

class _SqfliteAppDatabase extends AppDatabase {
  _SqfliteAppDatabase() : super._();

  sqflite.Database? _db;
  static const String _fileName = 'health_reset_plan.sqlite';
  static const int _schemaVersion = 1;

  Future<sqflite.Database> _ensureDb() async {
    if (_db != null) return _db!;

    if (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      ffi.sqfliteFfiInit();
      sqflite.databaseFactory = ffi.databaseFactoryFfi;
    }

    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, _fileName);
    _db = await sqflite.databaseFactory.openDatabase(
      path,
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
    return db.query(
      table,
      where: where,
      whereArgs: whereArgs,
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
    return db.insert(
      table,
      values,
      conflictAlgorithm:
          replace ? sqflite.ConflictAlgorithm.replace : null,
    );
  }

  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    final db = await _ensureDb();
    return db.update(
      table,
      values,
      where: where,
      whereArgs: whereArgs,
    );
  }

  @override
  Future<int> delete(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    final db = await _ensureDb();
    return db.delete(
      table,
      where: where,
      whereArgs: whereArgs,
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
  Future<T> transaction<T>(Future<T> Function(AppDatabase txn) action) async {
    final db = await _ensureDb();
    return db.transaction((txn) async {
      return action(_SqfliteTransactionAppDatabase(txn));
    });
  }

  Future<void> _onCreate(sqflite.Database db, int version) async {
    await db.execute(_ddlUserProfile);
    await db.execute(_ddlHealthIndicator);
    await db.execute(_ddlPlan);
    await db.execute(_ddlClockRecord);
    await db.execute(_ddlReminder);
    await db.execute(_ddlSyncQueue);
  }

  Future<void> _onUpgrade(
      sqflite.Database db, int oldVersion, int newVersion) async {
    // 后续版本迁移在此追加。
  }
}

class _SqfliteTransactionAppDatabase extends AppDatabase {
  _SqfliteTransactionAppDatabase(this._txn) : super._();

  final sqflite.Transaction _txn;

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
    return _txn.query(
      table,
      where: where,
      whereArgs: whereArgs,
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
      values,
      conflictAlgorithm:
          replace ? sqflite.ConflictAlgorithm.replace : null,
    );
  }

  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
  }) {
    return _txn.update(
      table,
      values,
      where: where,
      whereArgs: whereArgs,
    );
  }

  @override
  Future<int> delete(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) {
    return _txn.delete(
      table,
      where: where,
      whereArgs: whereArgs,
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
      version         INTEGER NOT NULL DEFAULT 0,
      is_dirty        INTEGER NOT NULL DEFAULT 1
    );
''';

const String _ddlHealthIndicator = '''
    CREATE TABLE IF NOT EXISTS health_indicator (
      id           INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id      TEXT    NOT NULL,
      type         TEXT    NOT NULL,
      payload_json TEXT    NOT NULL,
      source       TEXT    NOT NULL DEFAULT 'manual',
      measured_at  INTEGER NOT NULL,
      created_at   INTEGER NOT NULL,
      updated_at   INTEGER NOT NULL,
      version      INTEGER NOT NULL DEFAULT 0,
      is_dirty     INTEGER NOT NULL DEFAULT 1
    );
''';

const String _ddlPlan = '''
    CREATE TABLE IF NOT EXISTS plan (
      id           INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id      TEXT    NOT NULL,
      type         TEXT    NOT NULL,
      plan_date    INTEGER NOT NULL,
      payload_json TEXT    NOT NULL,
      ai_provider  TEXT    NOT NULL DEFAULT '',
      ai_model     TEXT    NOT NULL DEFAULT '',
      created_at   INTEGER NOT NULL,
      updated_at   INTEGER NOT NULL,
      version      INTEGER NOT NULL DEFAULT 0,
      is_dirty     INTEGER NOT NULL DEFAULT 1
    );
''';

const String _ddlClockRecord = '''
    CREATE TABLE IF NOT EXISTS clock_record (
      id          INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id     TEXT    NOT NULL,
      type        TEXT    NOT NULL,
      status      TEXT    NOT NULL DEFAULT 'done',
      clock_at    INTEGER NOT NULL,
      note        TEXT    NOT NULL DEFAULT '',
      photo_path  TEXT    NOT NULL DEFAULT '',
      created_at  INTEGER NOT NULL,
      updated_at  INTEGER NOT NULL,
      version     INTEGER NOT NULL DEFAULT 0,
      is_dirty    INTEGER NOT NULL DEFAULT 1
    );
''';

const String _ddlReminder = '''
    CREATE TABLE IF NOT EXISTS reminder (
      id           INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id      TEXT    NOT NULL,
      type         TEXT    NOT NULL,
      remind_at    INTEGER NOT NULL,
      payload_json TEXT    NOT NULL DEFAULT '',
      channel      TEXT    NOT NULL DEFAULT 'local',
      status       TEXT    NOT NULL DEFAULT 'pending',
      created_at   INTEGER NOT NULL,
      updated_at   INTEGER NOT NULL,
      version      INTEGER NOT NULL DEFAULT 0,
      is_dirty     INTEGER NOT NULL DEFAULT 1
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
