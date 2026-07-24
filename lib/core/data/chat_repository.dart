import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../storage/app_database.dart';

/// AI 对话会话
class ChatSession {
  ChatSession({
    required this.id,
    required this.title,
    required this.provider,
    required this.messageCount,
    required this.createdAt,
    required this.updatedAt,
    required this.sessionUuid,
  });

  final int id;
  final String title;
  final String provider;
  final int messageCount;
  final int createdAt;
  final int updatedAt;
  final String sessionUuid;

  factory ChatSession.fromRow(Map<String, Object?> row) => ChatSession(
        id: row['id'] as int,
        title: (row['title'] as String?) ?? '新对话',
        provider: (row['provider'] as String?) ?? 'deepseek',
        messageCount: (row['message_count'] as int?) ?? 0,
        createdAt: (row['created_at'] as int?) ?? 0,
        updatedAt: (row['updated_at'] as int?) ?? 0,
        sessionUuid: (row['session_uuid'] as String?) ?? '',
      );
}

/// AI 单条消息
class ChatMessage {
  ChatMessage({
    required this.id,
    required this.sessionId,
    required this.role,
    required this.content,
    required this.provider,
    required this.isError,
    required this.createdAt,
    required this.updatedAt,
    required this.messageUuid,
    required this.sessionUuid,
  });

  final int id;
  final int sessionId;
  final String role; // user / assistant
  final String content;
  final String provider;
  final bool isError;
  final int createdAt;
  final int updatedAt;
  final String messageUuid;
  final String sessionUuid;

  factory ChatMessage.fromRow(Map<String, Object?> row) => ChatMessage(
        id: row['id'] as int,
        sessionId: row['session_id'] as int,
        role: row['role'] as String,
        content: (row['content'] as String?) ?? '',
        provider: (row['provider'] as String?) ?? '',
        isError: ((row['is_error'] as int?) ?? 0) == 1,
        createdAt: (row['created_at'] as int?) ?? 0,
        updatedAt: (row['updated_at'] as int?) ?? (row['created_at'] as int?) ?? 0,
        messageUuid: (row['message_uuid'] as String?) ?? '',
        sessionUuid: (row['session_uuid'] as String?) ?? '',
      );

  Map<String, String> toApiFormat() => {
        'role': role,
        'content': content,
      };
}

/// AI 对话本地仓库 — 会话和消息 CRUD。
class ChatRepository {
  ChatRepository({required AppDatabase database}) : _database = database;
  final AppDatabase _database;
  static const _uuid = Uuid();

  // ── 会话 ─────────────────────────────────────────────────────

  /// 创建新会话，返回新 id
  Future<int> createSession({
    required String provider,
    String title = '新对话',
  }) async {
    final db = await _database.open();
    final now = DateTime.now().millisecondsSinceEpoch;
    return db.insert('ai_session', {
      'title': title,
      'provider': provider,
      'message_count': 0,
      'created_at': now,
      'updated_at': now,
      'session_uuid': _uuid.v4(),
      'version': now,
      'is_dirty': 1,
      'sync_at': 0,
    });
  }

  /// 加载所有会话，按最近活跃排序
  Future<List<ChatSession>> listSessions() async {
    final db = await _database.open();
    final rows = await db.query(
      'ai_session',
      orderBy: 'updated_at DESC',
      limit: 100,
    );
    return rows.map(ChatSession.fromRow).toList();
  }

  /// 删除会话（连同消息一起）
  Future<void> deleteSession(int sessionId) async {
    final db = await _database.open();
    await db.transaction((txn) async {
      await _ensureUuids(txn);
      final sessionRows = await txn.query('ai_session', where: 'id = ?', whereArgs: [sessionId]);
      if (sessionRows.isEmpty) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      final sessionUuid = sessionRows.first['session_uuid'] as String;
      final messages = await txn.query('ai_message', where: 'session_id = ?', whereArgs: [sessionId]);
      for (final message in messages) {
        await _enqueueDelete(txn, 'ai_message', message['id'] as int,
            message['message_uuid'] as String, now);
      }
      await _enqueueDelete(txn, 'ai_session', sessionId, sessionUuid, now);
      await txn.delete('ai_message', where: 'session_id = ?', whereArgs: [sessionId]);
      await txn.delete('ai_session',
          where: 'id = ?', whereArgs: [sessionId]);
    });
  }

  /// 重命名会话
  Future<void> renameSession(int sessionId, String title) async {
    final db = await _database.open();
    await db.update(
      'ai_session',
      {
        'title': title,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
        'version': DateTime.now().millisecondsSinceEpoch,
        'is_dirty': 1,
      },
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  // ── 消息 ─────────────────────────────────────────────────────

  /// 加载某会话下的全部消息（按时间顺序）
  Future<List<ChatMessage>> loadMessages(int sessionId) async {
    final db = await _database.open();
    final rows = await db.query(
      'ai_message',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'id ASC',
    );
    return rows.map(ChatMessage.fromRow).toList();
  }

  /// 插入一条消息，自动 +1 会话计数 + 更新 updated_at
  /// 第一条 user 消息会自动作为会话标题
  Future<int> addMessage({
    required int sessionId,
    required String role,
    required String content,
    String provider = '',
    bool isError = false,
  }) async {
    final db = await _database.open();
    final now = DateTime.now().millisecondsSinceEpoch;
    int msgId = -1;

    await db.transaction((txn) async {
      msgId = await txn.insert('ai_message', {
        'session_id': sessionId,
        'role': role,
        'content': content,
        'provider': provider,
        'is_error': isError ? 1 : 0,
        'created_at': now,
        'updated_at': now,
        'message_uuid': _uuid.v4(),
        'session_uuid': (await txn.query('ai_session', where: 'id = ?', whereArgs: [sessionId], limit: 1)).first['session_uuid'],
        'version': now,
        'is_dirty': 1,
        'sync_at': 0,
      });

      // 查询当前会话，准备更新计数 + 可能的标题
      final sessions = await txn.query(
        'ai_session',
        where: 'id = ?',
        whereArgs: [sessionId],
        limit: 1,
      );
      if (sessions.isEmpty) return;
      final session = sessions.first;
      final currentCount = (session['message_count'] as int?) ?? 0;
      final currentTitle = (session['title'] as String?) ?? '';

      // 第一条 user 消息自动作为会话标题
      String? autoTitle;
      if (role == 'user' &&
          currentCount == 0 &&
          (currentTitle.isEmpty || currentTitle == '新对话')) {
        final clean = content.trim().replaceAll(RegExp(r'\s+'), ' ');
        autoTitle = clean.length > 24 ? '${clean.substring(0, 24)}…' : clean;
      }

      await txn.update(
        'ai_session',
        {
          'message_count': currentCount + 1,
          'updated_at': now,
          'version': now,
          'is_dirty': 1,
          if (autoTitle != null) 'title': autoTitle,
        },
        where: 'id = ?',
        whereArgs: [sessionId],
      );
    });

    return msgId;
  }

  /// 更新一条消息内容（用于流式 token 累加完成后保存最终内容）
  Future<void> updateMessageContent({
    required int messageId,
    required String content,
    bool isError = false,
  }) async {
    final db = await _database.open();
    await db.update(
      'ai_message',
      {
        'content': content,
        'is_error': isError ? 1 : 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
        'version': DateTime.now().millisecondsSinceEpoch,
        'is_dirty': 1,
      },
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  /// 清空所有会话与消息（调试用）
  Future<void> clearAll() async {
    final db = await _database.open();
    await db.transaction((txn) async {
      await txn.delete('ai_message');
      await txn.delete('ai_session');
    });
  }

  Future<void> prepareForSync() async {
    final db = await _database.open();
    await db.transaction(_ensureUuids);
  }

  Future<void> recalculateMessageCounts() async {
    final db = await _database.open();
    final sessions = await db.query('ai_session');
    for (final session in sessions) {
      final count = await db.count('ai_message', where: 'session_id = ?', whereArgs: [session['id']]);
      if (count != session['message_count']) {
        await db.update('ai_session', {'message_count': count}, where: 'id = ?', whereArgs: [session['id']]);
      }
    }
  }

  Future<void> _ensureUuids(AppDatabase db) async {
    final sessions = await db.query('ai_session');
    for (final session in sessions) {
      var sessionUuid = session['session_uuid'] as String? ?? '';
      if (sessionUuid.isEmpty) {
        sessionUuid = _uuid.v4();
        final now = DateTime.now().millisecondsSinceEpoch;
        await db.update('ai_session', {
          'session_uuid': sessionUuid, 'updated_at': now, 'version': now, 'is_dirty': 1, 'sync_at': 0,
        }, where: 'id = ?', whereArgs: [session['id']]);
      }
      final messages = await db.query('ai_message', where: 'session_id = ?', whereArgs: [session['id']]);
      for (final message in messages) {
        if ((message['message_uuid'] as String? ?? '').isNotEmpty &&
            (message['session_uuid'] as String? ?? '').isNotEmpty) {
          continue;
        }
        final now = DateTime.now().millisecondsSinceEpoch;
        await db.update('ai_message', {
          'message_uuid': (message['message_uuid'] as String? ?? '').isEmpty ? _uuid.v4() : message['message_uuid'],
          'session_uuid': sessionUuid,
          'updated_at': (message['updated_at'] as int? ?? 0) > 0 ? message['updated_at'] : now,
          'version': (message['version'] as int? ?? 0) > 0 ? message['version'] : now,
          'is_dirty': 1,
          'sync_at': 0,
        }, where: 'id = ?', whereArgs: [message['id']]);
      }
    }
  }

  Future<void> _enqueueDelete(AppDatabase db, String table, int rowId, String clientId, int now) {
    return db.insert('sync_queue', {
      'table_name': table, 'row_id': rowId, 'op': 'delete',
      'payload_json': jsonEncode({'table': table, 'clientId': clientId, 'version': now, 'clientUpdatedAt': now}),
      'created_at': now, 'updated_at': now,
    }).then((_) {});
  }
}
