enum QuitSmokingMode { immediate, gradual }

enum QuitSmokingEventType { smoked, craving, checkIn }

class QuitSmokingProfile {
  const QuitSmokingProfile({
    this.id,
    required this.mode,
    required this.dailyBaseline,
    required this.packCigarettes,
    required this.packPrice,
    required this.smokingYears,
    required this.targetDate,
    required this.motivation,
    required this.triggers,
    required this.stageGoal,
    required this.stageStartDate,
    required this.remindersEnabled,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final QuitSmokingMode mode;
  final int dailyBaseline;
  final int packCigarettes;
  final double packPrice;
  final int smokingYears;
  final int targetDate;
  final String motivation;
  final List<String> triggers;
  final int stageGoal;
  final int stageStartDate;
  final bool remindersEnabled;
  final int createdAt;
  final int updatedAt;

  Map<String, Object?> toRow() => {
        'mode': mode.name,
        'daily_baseline': dailyBaseline,
        'pack_cigarettes': packCigarettes,
        'pack_price': packPrice,
        'smoking_years': smokingYears,
        'target_date': targetDate,
        'motivation': motivation,
        'triggers_json': triggers,
        'stage_goal': stageGoal,
        'stage_start_date': stageStartDate,
        'reminders_enabled': remindersEnabled ? 1 : 0,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory QuitSmokingProfile.fromRow(Map<String, Object?> row) {
    final rawTriggers = row['triggers_json'];
    return QuitSmokingProfile(
      id: _asInt(row['id']),
      mode: row['mode'] == 'gradual'
          ? QuitSmokingMode.gradual
          : QuitSmokingMode.immediate,
      dailyBaseline: _asInt(row['daily_baseline']) ?? 0,
      packCigarettes: _asInt(row['pack_cigarettes']) ?? 20,
      packPrice: _asDouble(row['pack_price']) ?? 0,
      smokingYears: _asInt(row['smoking_years']) ?? 0,
      targetDate: _asInt(row['target_date']) ?? 0,
      motivation: row['motivation'] as String? ?? '',
      triggers: rawTriggers is List
          ? rawTriggers.map((item) => '$item').toList()
          : const [],
      stageGoal: _asInt(row['stage_goal']) ?? 0,
      stageStartDate: _asInt(row['stage_start_date']) ?? 0,
      remindersEnabled: _asInt(row['reminders_enabled']) == 1,
      createdAt: _asInt(row['created_at']) ?? 0,
      updatedAt: _asInt(row['updated_at']) ?? 0,
    );
  }
}

class QuitSmokingEvent {
  const QuitSmokingEvent({
    this.id,
    required this.type,
    required this.occurredAt,
    required this.cigarettes,
    required this.intensity,
    required this.success,
    required this.trigger,
    required this.strategy,
    required this.note,
    required this.createdAt,
  });

  final int? id;
  final QuitSmokingEventType type;
  final int occurredAt;
  final int cigarettes;
  final int intensity;
  final bool? success;
  final String trigger;
  final String strategy;
  final String note;
  final int createdAt;

  QuitSmokingEvent copyWith({
    QuitSmokingEventType? type,
    int? occurredAt,
    int? cigarettes,
    int? intensity,
    bool? success,
    String? trigger,
    String? strategy,
    String? note,
  }) =>
      QuitSmokingEvent(
        id: id,
        type: type ?? this.type,
        occurredAt: occurredAt ?? this.occurredAt,
        cigarettes: cigarettes ?? this.cigarettes,
        intensity: intensity ?? this.intensity,
        success: success ?? this.success,
        trigger: trigger ?? this.trigger,
        strategy: strategy ?? this.strategy,
        note: note ?? this.note,
        createdAt: createdAt,
      );

  Map<String, Object?> toRow() => {
        'event_type': type.name,
        'occurred_at': occurredAt,
        'cigarettes': cigarettes,
        'intensity': intensity,
        'success': success == null ? null : (success! ? 1 : 0),
        'trigger_text': trigger,
        'strategy': strategy,
        'note': note,
        'created_at': createdAt,
      };

  factory QuitSmokingEvent.fromRow(Map<String, Object?> row) {
    final success = _asInt(row['success']);
    return QuitSmokingEvent(
      id: _asInt(row['id']),
      type: switch (row['event_type']) {
        'craving' => QuitSmokingEventType.craving,
        'checkIn' => QuitSmokingEventType.checkIn,
        _ => QuitSmokingEventType.smoked,
      },
      occurredAt: _asInt(row['occurred_at']) ?? 0,
      cigarettes: _asInt(row['cigarettes']) ?? 1,
      intensity: _asInt(row['intensity']) ?? 0,
      success: success == null ? null : success == 1,
      trigger: row['trigger_text'] as String? ?? '',
      strategy: row['strategy'] as String? ?? '',
      note: row['note'] as String? ?? '',
      createdAt: _asInt(row['created_at']) ?? 0,
    );
  }
}

bool shouldInvalidateCheckIn({
  required QuitSmokingEvent checkIn,
  required Iterable<QuitSmokingEvent> events,
}) {
  if (checkIn.type != QuitSmokingEventType.checkIn) return false;
  final checkInTime = DateTime.fromMillisecondsSinceEpoch(checkIn.occurredAt);
  return events.any((event) {
    if (event.type != QuitSmokingEventType.smoked ||
        event.createdAt <= checkIn.createdAt) {
      return false;
    }
    final eventTime = DateTime.fromMillisecondsSinceEpoch(event.occurredAt);
    return eventTime.year == checkInTime.year &&
        eventTime.month == checkInTime.month &&
        eventTime.day == checkInTime.day;
  });
}

int calculateCheckInStreak({
  required Iterable<QuitSmokingEvent> events,
  required DateTime through,
}) {
  final checkInDays = events
      .where((event) =>
          event.type == QuitSmokingEventType.checkIn && event.success == true)
      .map((event) {
    final time = DateTime.fromMillisecondsSinceEpoch(event.occurredAt);
    return DateTime(time.year, time.month, time.day);
  }).toSet();
  var day = DateTime(through.year, through.month, through.day);
  var streak = 0;
  while (checkInDays.contains(day)) {
    streak++;
    day = day.subtract(const Duration(days: 1));
  }
  return streak;
}

class QuitSmokingProgress {
  const QuitSmokingProgress({
    required this.smokeFreeDays,
    required this.todayCount,
    required this.avoidedCigarettes,
    required this.savedMoney,
    required this.todaySavedMoney,
    required this.startedAt,
    required this.smokeFreeStartedAt,
  });

  final int smokeFreeDays;
  final int todayCount;
  final int avoidedCigarettes;
  final double savedMoney;
  final double todaySavedMoney;
  final DateTime startedAt;
  final DateTime smokeFreeStartedAt;
}

QuitSmokingProgress calculateQuitSmokingProgress({
  required QuitSmokingProfile profile,
  required Iterable<QuitSmokingEvent> events,
  required DateTime now,
}) {
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime.fromMillisecondsSinceEpoch(profile.targetDate);
  final targetDay = DateTime(target.year, target.month, target.day);
  final stageStart = DateTime.fromMillisecondsSinceEpoch(
    profile.stageStartDate > 0 ? profile.stageStartDate : profile.targetDate,
  );
  final startedAt =
      profile.mode == QuitSmokingMode.immediate && targetDay.isAfter(today)
          ? targetDay
          : stageStart;
  final start = DateTime(startedAt.year, startedAt.month, startedAt.day);
  final smoked = events
      .where((event) => event.type == QuitSmokingEventType.smoked)
      .toList();
  final todayCount = smoked.where((event) {
    final time = DateTime.fromMillisecondsSinceEpoch(event.occurredAt);
    return time.year == today.year &&
        time.month == today.month &&
        time.day == today.day;
  }).fold<int>(0, (sum, event) => sum + event.cigarettes);

  if (today.isBefore(start)) {
    return QuitSmokingProgress(
      smokeFreeDays: 0,
      todayCount: todayCount,
      avoidedCigarettes: 0,
      savedMoney: 0,
      todaySavedMoney: 0,
      startedAt: startedAt,
      smokeFreeStartedAt: startedAt,
    );
  }

  final actualSinceStart = smoked
      .where((event) => event.occurredAt >= start.millisecondsSinceEpoch)
      .fold<int>(0, (sum, event) => sum + event.cigarettes);
  final planDays = today.difference(start).inDays + 1;
  final avoided = (profile.dailyBaseline * planDays - actualSinceStart)
      .clamp(0, 1000000)
      .toInt();
  final savedMoney = profile.packCigarettes <= 0
      ? 0.0
      : avoided / profile.packCigarettes * profile.packPrice;
  final todayAvoided = (profile.dailyBaseline - todayCount)
      .clamp(0, profile.dailyBaseline)
      .toInt();
  final todaySavedMoney = profile.packCigarettes <= 0
      ? 0.0
      : todayAvoided / profile.packCigarettes * profile.packPrice;
  final lastSmoke = smoked
      .where((event) => event.occurredAt >= start.millisecondsSinceEpoch)
      .fold<QuitSmokingEvent?>(
        null,
        (latest, event) =>
            latest == null || event.occurredAt > latest.occurredAt
                ? event
                : latest,
      );
  final smokeFreeStart = lastSmoke == null
      ? startedAt
      : DateTime.fromMillisecondsSinceEpoch(lastSmoke.occurredAt);

  return QuitSmokingProgress(
    smokeFreeDays: now.difference(smokeFreeStart).inHours ~/ 24,
    todayCount: todayCount,
    avoidedCigarettes: avoided,
    savedMoney: savedMoney,
    todaySavedMoney: todaySavedMoney,
    startedAt: startedAt,
    smokeFreeStartedAt: smokeFreeStart,
  );
}

int? _asInt(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value');

double? _asDouble(Object? value) =>
    value is num ? value.toDouble() : double.tryParse('$value');
