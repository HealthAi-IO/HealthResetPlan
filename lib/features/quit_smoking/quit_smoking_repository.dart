import '../../core/storage/app_database.dart';
import 'quit_smoking_models.dart';

class QuitSmokingRepository {
  QuitSmokingRepository({required this.database});

  final AppDatabase database;

  Future<QuitSmokingProfile?> loadProfile() async {
    final rows = await database.open().then(
          (db) => db.query('quit_smoking_profile', limit: 1),
        );
    return rows.isEmpty ? null : QuitSmokingProfile.fromRow(rows.first);
  }

  Future<QuitSmokingProfile> saveProfile({
    required QuitSmokingMode mode,
    required int dailyBaseline,
    required int packCigarettes,
    required double packPrice,
    required int smokingYears,
    required DateTime targetDate,
    required String motivation,
    required List<String> triggers,
    required int stageGoal,
    required DateTime stageStartDate,
    required bool remindersEnabled,
  }) async {
    final db = await database.open();
    final old = await loadProfile();
    final now = DateTime.now().millisecondsSinceEpoch;
    final profile = QuitSmokingProfile(
      id: old?.id,
      mode: mode,
      dailyBaseline: dailyBaseline,
      packCigarettes: packCigarettes,
      packPrice: packPrice,
      smokingYears: smokingYears,
      targetDate: _dateOnly(targetDate),
      motivation: motivation,
      triggers: triggers,
      stageGoal: stageGoal,
      stageStartDate: old?.stageStartDate ?? stageStartDate.millisecondsSinceEpoch,
      remindersEnabled: remindersEnabled,
      createdAt: old?.createdAt ?? now,
      updatedAt: now,
    );
    if (old == null) {
      final id = await db.insert('quit_smoking_profile', profile.toRow());
      return QuitSmokingProfile.fromRow({...profile.toRow(), 'id': id});
    }
    await db.update(
      'quit_smoking_profile',
      profile.toRow(),
      where: 'id = ?',
      whereArgs: [old.id],
    );
    return profile;
  }

  Future<List<QuitSmokingEvent>> loadEvents({int limit = 5000}) async {
    final rows = await database.open().then(
          (db) => db.query(
            'smoking_event',
            orderBy: 'occurred_at DESC',
            limit: limit,
          ),
        );
    return rows.map(QuitSmokingEvent.fromRow).toList();
  }

  Future<QuitSmokingEvent> addEvent({
    required QuitSmokingEventType type,
    required int cigarettes,
    required int intensity,
    required bool? success,
    required String trigger,
    required String strategy,
    required String note,
  }) async {
    final db = await database.open();
    final now = DateTime.now().millisecondsSinceEpoch;
    final event = QuitSmokingEvent(
      type: type,
      occurredAt: now,
      cigarettes: cigarettes,
      intensity: intensity,
      success: success,
      trigger: trigger,
      strategy: strategy,
      note: note,
      createdAt: now,
    );
    final id = await db.insert('smoking_event', event.toRow());
    return QuitSmokingEvent.fromRow({...event.toRow(), 'id': id});
  }

  Future<void> deleteAll() async {
    final db = await database.open();
    await db.delete('quit_smoking_profile');
    await db.delete('smoking_event');
  }

  static int _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day).millisecondsSinceEpoch;
}
