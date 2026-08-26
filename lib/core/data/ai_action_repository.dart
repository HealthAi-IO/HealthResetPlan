import '../storage/app_database.dart';
import 'health_models.dart';

class AiActionRepository {
  static final instance = AiActionRepository._();
  AiActionRepository._();

  Future<int> recordConfirmed({
    required String type,
    required String title,
    required String detail,
    String? targetTable,
    int? targetId,
  }) async {
    final db = await AppDatabase.instance.open();
    return db.insert('ai_action_log', {
      'user_id': kLocalUserId,
      'action_type': type,
      'title': title,
      'detail': detail,
      if (targetTable != null) 'target_table': targetTable,
      if (targetId != null) 'target_id': targetId,
      'status': 'confirmed',
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<bool> undo(int id) async {
    final db = await AppDatabase.instance.open();
    final rows = await db.query('ai_action_log',
        where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return false;
    final createdAt = int.tryParse('${rows.first['created_at']}') ?? 0;
    if (DateTime.now().millisecondsSinceEpoch - createdAt >
        const Duration(minutes: 30).inMilliseconds) {
      return false;
    }
    await db.update(
        'ai_action_log',
        {
          'status': 'undone',
          'undone_at': DateTime.now().millisecondsSinceEpoch
        },
        where: 'id = ?',
        whereArgs: [id]);
    return true;
  }

  Future<List<Map<String, Object?>>> recent({int limit = 20}) async {
    final db = await AppDatabase.instance.open();
    return db.query(
      'ai_action_log',
      orderBy: 'created_at DESC',
      limit: limit,
    );
  }
}
