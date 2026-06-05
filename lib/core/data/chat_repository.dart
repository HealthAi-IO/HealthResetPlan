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
  });

  final int id;
  final String title;
  final String provider;
  final int messageCount;
  final int createdAt;
  final int updatedAt;

  factory ChatSession.fromRow(Map<String, Object?> row) => ChatSession(
        id: row['id'] as int,
        title: (row['title'] as String?) ?? '新对话',
        provider: (row['provider'] as String?) ?? 'deepseek',
        messageCount: (row['message_count'] as int?) ?? 0,
        createdAt: (row['created_at'] as int?) ?? 0,
        updatedAt: (row['updated_at'] as int?) ?? 0,
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
  });

  final int id;
  final int sessionId;
  final String role; // user / assistant
  final String content;
  final String provider;
  final bool isError;
  final int createdAt;

  factory ChatMessage.fromRow(Map<String, Object?> row) => ChatMessage(
        id: row['id'] as int,
        sessionId: row['session_id'] as int,
        role: row['role'] as String,
        content: (row['content'] as String?) ?? '',
        provider: (row['provider'] as String?) ?? '',
        isError: ((row['is_error'] as int?) ?? 0) == 1,
        createdAt: (row['created_at'] as int?) ?? 0,
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
      await txn.delete('ai_message',
          where: 'session_id = ?', whereArgs: [sessionId]);
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
}
