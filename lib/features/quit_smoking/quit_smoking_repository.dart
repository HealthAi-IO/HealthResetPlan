import '../../core/storage/app_database.dart';
import 'quit_smoking_models.dart';

class QuitSmokingRepository {
  QuitSmokingRepository({required this.database});

  final AppDatabase database;

  Future<QuitSmokingProfile?> loadProfile() async {
    final db = await database.open();
    final rows = await db.query('quit_smoking_profile', limit: 1);
    if (rows.isEmpty) return null;
    final profile = QuitSmokingProfile.fromRow(rows.first);
    if (profile.mode != QuitSmokingMode.gradual ||
        profile.planDurationDays > 0) {
      return profile;
    }
    final tomorrow =
        _dateOnlyValue(DateTime.now().add(const Duration(days: 1)));
    final migrated = profile.copyWith(
      planStartDate: tomorrow.millisecondsSinceEpoch,
      targetDate: tomorrow.add(const Duration(days: 13)).millisecondsSinceEpoch,
      planDurationDays: 14,
      planStartTarget: profile.stageGoal > 0
          ? profile.stageGoal.clamp(1, profile.dailyBaseline)
          : profile.dailyBaseline,
      extendedStageIndexes: const [],
      needsReplan: false,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _updateProfile(db, migrated);
    return migrated;
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
    int planDurationDays = 14,
    int? planStartTarget,
    bool restartPlan = false,
  }) async {
    final db = await database.open();
    final old = await loadProfile();
    final now = DateTime.now().millisecondsSinceEpoch;
    final shouldRestart = old == null || old.mode != mode || restartPlan;
    final gradualStart = shouldRestart
        ? _dateOnlyValue(stageStartDate)
        : DateTime.fromMillisecondsSinceEpoch(old.stageStartDate);
    final gradualDuration = planDurationDays.clamp(7, 28);
    final profile = QuitSmokingProfile(
      id: old?.id,
      mode: mode,
      dailyBaseline: dailyBaseline,
      packCigarettes: packCigarettes,
      packPrice: packPrice,
      smokingYears: smokingYears,
      targetDate: mode == QuitSmokingMode.gradual
          ? (shouldRestart
              ? gradualStart
                  .add(Duration(days: gradualDuration - 1))
                  .millisecondsSinceEpoch
              : old.targetDate)
          : _dateOnly(targetDate),
      motivation: motivation,
      triggers: triggers,
      stageGoal: stageGoal,
      stageStartDate:
          old?.stageStartDate ?? stageStartDate.millisecondsSinceEpoch,
      planStartDate: mode == QuitSmokingMode.gradual
          ? (shouldRestart
              ? gradualStart.millisecondsSinceEpoch
              : old.planStartDate > 0
                  ? old.planStartDate
                  : old.stageStartDate)
          : 0,
      planDurationDays: mode == QuitSmokingMode.gradual
          ? (shouldRestart ? gradualDuration : old.planDurationDays)
          : 0,
      planStartTarget: mode == QuitSmokingMode.gradual
          ? (shouldRestart
              ? (planStartTarget ?? dailyBaseline).clamp(1, dailyBaseline)
              : old.planStartTarget)
          : 0,
      extendedStageIndexes: mode == QuitSmokingMode.gradual && !shouldRestart
          ? old.extendedStageIndexes
          : const [],
      needsReplan: mode == QuitSmokingMode.gradual && !shouldRestart
          ? old.needsReplan
          : false,
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

  Future<QuitSmokingProfile> evaluateAdaptivePlan({
    required QuitSmokingProfile profile,
    required List<QuitSmokingEvent> events,
    required DateTime now,
  }) async {
    final db = await database.open();
    final stageIndex = adaptiveStageToExtend(
      profile: profile,
      events: events,
      now: now,
    );
    if (stageIndex != null) {
      final updated = profile.copyWith(
        extendedStageIndexes: [...profile.extendedStageIndexes, stageIndex],
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      await _updateProfile(db, updated);
      return updated;
    }
    if (shouldSuggestGradualReplan(
      profile: profile,
      events: events,
      now: now,
    )) {
      final updated = profile.copyWith(
        needsReplan: true,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      await _updateProfile(db, updated);
      return updated;
    }
    return profile;
  }

  Future<QuitSmokingProfile> continueCurrentStage({
    required QuitSmokingProfile profile,
    required DateTime now,
  }) async {
    final stage = buildGradualQuitPlan(profile).stageFor(now);
    if (stage.target == 0) return profile;
    final updated = profile.copyWith(
      extendedStageIndexes: [...profile.extendedStageIndexes, stage.index],
      needsReplan: false,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _updateProfile(await database.open(), updated);
    return updated;
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
    DateTime? occurredAt,
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
      occurredAt: (occurredAt ?? DateTime.now()).millisecondsSinceEpoch,
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

  Future<void> updateEvent(QuitSmokingEvent event) async {
    if (event.id == null) return;
    final db = await database.open();
    await db.update(
      'smoking_event',
      event.toRow(),
      where: 'id = ?',
      whereArgs: [event.id],
    );
  }

  Future<void> deleteEvent(QuitSmokingEvent event) async {
    if (event.id == null) return;
    final db = await database.open();
    await db.delete(
      'smoking_event',
      where: 'id = ?',
      whereArgs: [event.id],
    );
  }

  Future<QuitSmokingEvent?> invalidateCheckInForDay(DateTime day) async {
    final events = await loadEvents();
    for (final event in events) {
      if (event.type != QuitSmokingEventType.checkIn) continue;
      final time = DateTime.fromMillisecondsSinceEpoch(event.occurredAt);
      if (time.year == day.year &&
          time.month == day.month &&
          time.day == day.day) {
        await deleteEvent(event);
        return event;
      }
    }
    return null;
  }

  Future<void> deleteAll() async {
    final db = await database.open();
    await db.delete('quit_smoking_profile');
    await db.delete('smoking_event');
  }

  static int _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day).millisecondsSinceEpoch;

  static DateTime _dateOnlyValue(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static Future<void> _updateProfile(
    AppDatabase db,
    QuitSmokingProfile profile,
  ) =>
      db.update(
        'quit_smoking_profile',
        profile.toRow(),
        where: 'id = ?',
        whereArgs: [profile.id],
      );
}
