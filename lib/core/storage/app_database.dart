import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

/// 跨平台 SQLite 数据库管理。
///
/// 客户端数据 **必须** 先入 SQLite，之后才决定是否加密同步到服务端。
class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  Database? _db;
  static const String _fileName = 'health_reset_plan.sqlite';
  static const int _schemaVersion = 1;

  Future<Database> open() async {
    if (_db != null) return _db!;

    if (kIsWeb) {
      databaseFactory = databaseFactoryFfiWeb;
      _db = await databaseFactory.openDatabase(
        _fileName,
        options: OpenDatabaseOptions(
          version: _schemaVersion,
          onCreate: _onCreate,
          onUpgrade: _onUpgrade,
        ),
      );
      return _db!;
    }

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, _fileName);
    _db = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: _schemaVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON;');
          await db.execute('PRAGMA journal_mode = WAL;');
        },
      ),
    );
    return _db!;
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute(_ddlUserProfile);
    await db.execute(_ddlHealthIndicator);
    await db.execute(_ddlPlan);
    await db.execute(_ddlClockRecord);
    await db.execute(_ddlReminder);
    await db.execute(_ddlSyncQueue);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // 后续版本迁移在此追加。
  }

  // ---- DDL ----

  static const String _ddlUserProfile = '''
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

  static const String _ddlHealthIndicator = '''
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

  static const String _ddlPlan = '''
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

  static const String _ddlClockRecord = '''
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

  static const String _ddlReminder = '''
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
  static const String _ddlSyncQueue = '''
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
}
