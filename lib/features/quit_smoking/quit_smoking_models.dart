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
    this.planStartDate = 0,
    this.planDurationDays = 0,
    this.planStartTarget = 0,
    this.extendedStageIndexes = const [],
    this.needsReplan = false,
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
  final int planStartDate;
  final int planDurationDays;
  final int planStartTarget;
  final List<int> extendedStageIndexes;
  final bool needsReplan;
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
        'plan_start_date': planStartDate,
        'plan_duration_days': planDurationDays,
        'plan_start_target': planStartTarget,
        'extended_stage_indexes_json': extendedStageIndexes,
        'needs_replan': needsReplan ? 1 : 0,
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
      planStartDate: _asInt(row['plan_start_date']) ?? 0,
      planDurationDays: _asInt(row['plan_duration_days']) ?? 0,
      planStartTarget: _asInt(row['plan_start_target']) ?? 0,
      extendedStageIndexes: _asIntList(row['extended_stage_indexes_json']),
      needsReplan: _asInt(row['needs_replan']) == 1,
      remindersEnabled: _asInt(row['reminders_enabled']) == 1,
      createdAt: _asInt(row['created_at']) ?? 0,
      updatedAt: _asInt(row['updated_at']) ?? 0,
    );
  }

  QuitSmokingProfile copyWith({
    QuitSmokingMode? mode,
    int? dailyBaseline,
    int? packCigarettes,
    double? packPrice,
    int? smokingYears,
    int? targetDate,
    String? motivation,
    List<String>? triggers,
    int? stageGoal,
    int? stageStartDate,
    int? planStartDate,
    int? planDurationDays,
    int? planStartTarget,
    List<int>? extendedStageIndexes,
    bool? needsReplan,
    bool? remindersEnabled,
    int? updatedAt,
  }) =>
      QuitSmokingProfile(
        id: id,
        mode: mode ?? this.mode,
        dailyBaseline: dailyBaseline ?? this.dailyBaseline,
        packCigarettes: packCigarettes ?? this.packCigarettes,
        packPrice: packPrice ?? this.packPrice,
        smokingYears: smokingYears ?? this.smokingYears,
        targetDate: targetDate ?? this.targetDate,
        motivation: motivation ?? this.motivation,
        triggers: triggers ?? this.triggers,
        stageGoal: stageGoal ?? this.stageGoal,
        stageStartDate: stageStartDate ?? this.stageStartDate,
        planStartDate: planStartDate ?? this.planStartDate,
        planDurationDays: planDurationDays ?? this.planDurationDays,
        planStartTarget: planStartTarget ?? this.planStartTarget,
        extendedStageIndexes: extendedStageIndexes ?? this.extendedStageIndexes,
        needsReplan: needsReplan ?? this.needsReplan,
        remindersEnabled: remindersEnabled ?? this.remindersEnabled,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

class QuitSmokingStage {
  const QuitSmokingStage({
    required this.index,
    required this.target,
    required this.start,
    required this.originalEnd,
    required this.end,
  });

  final int index;
  final int target;
  final DateTime start;
  final DateTime originalEnd;
  final DateTime end;

  bool contains(DateTime day) => !day.isBefore(start) && !day.isAfter(end);
}

class GradualQuitPlan {
  const GradualQuitPlan({
    required this.stages,
    required this.quitDate,
    required this.needsReplan,
  });

  final List<QuitSmokingStage> stages;
  final DateTime quitDate;
  final bool needsReplan;

  QuitSmokingStage stageFor(DateTime day) {
    final normalized = _dateOnly(day);
    return stages.firstWhere(
      (stage) => stage.contains(normalized),
      orElse: () =>
          normalized.isBefore(stages.first.start) ? stages.first : stages.last,
    );
  }
}

GradualQuitPlan buildGradualQuitPlan(QuitSmokingProfile profile) {
  final start = _dateOnly(DateTime.fromMillisecondsSinceEpoch(
    profile.planStartDate > 0
        ? profile.planStartDate
        : profile.stageStartDate > 0
            ? profile.stageStartDate
            : profile.targetDate,
  ));
  final duration = profile.planDurationDays > 0
      ? profile.planDurationDays.clamp(7, 28).toInt()
      : 14;
  final startTarget = (profile.planStartTarget > 0
          ? profile.planStartTarget
          : profile.stageGoal > 0
              ? profile.stageGoal
              : profile.dailyBaseline)
      .clamp(1, profile.dailyBaseline.clamp(1, 200))
      .toInt();
  final targets = gradualTargetsFor(
    startTarget: startTarget,
    durationDays: duration,
  );
  final stageCount = targets.length;
  final gradualDays = duration - 1;
  final baseLength = gradualDays ~/ stageCount;
  final remainder = gradualDays % stageCount;
  final extensionCounts = <int, int>{};
  for (final index in profile.extendedStageIndexes) {
    extensionCounts[index] = (extensionCounts[index] ?? 0) + 1;
  }

  final stages = <QuitSmokingStage>[];
  var cursor = start;
  for (var index = 0; index < stageCount; index++) {
    final receivesRemainder = index >= stageCount - remainder;
    final length = baseLength + (receivesRemainder ? 1 : 0);
    final target = targets[index];
    final originalEnd = cursor.add(Duration(days: length - 1));
    final extensionDays = (extensionCounts[index] ?? 0) * 3;
    final end = originalEnd.add(Duration(days: extensionDays));
    stages.add(QuitSmokingStage(
      index: index,
      target: target,
      start: cursor,
      originalEnd: originalEnd,
      end: end,
    ));
    cursor = end.add(const Duration(days: 1));
  }
  stages.add(QuitSmokingStage(
    index: stageCount,
    target: 0,
    start: cursor,
    originalEnd: DateTime(9999, 12, 31),
    end: DateTime(9999, 12, 31),
  ));
  return GradualQuitPlan(
    stages: stages,
    quitDate: cursor,
    needsReplan: profile.needsReplan,
  );
}

List<int> gradualTargetsFor({
  required int startTarget,
  required int durationDays,
}) {
  final normalizedTarget = startTarget.clamp(1, 200).toInt();
  final preferredStageCount = durationDays > 14 ? 6 : 3;
  final maximumStages = (normalizedTarget - 1).clamp(1, 6).toInt();
  final stageCount = preferredStageCount.clamp(1, maximumStages).toInt();
  return [
    for (var index = 0; index < stageCount; index++)
      (normalizedTarget * (stageCount - index) ~/ (stageCount + 1))
          .clamp(1, normalizedTarget)
          .toInt(),
  ];
}

int quitSmokingTargetForDay({
  required QuitSmokingProfile profile,
  required Iterable<QuitSmokingEvent> events,
  required DateTime day,
}) {
  final checkIn = events.where((event) {
    if (event.type != QuitSmokingEventType.checkIn) return false;
    final time = DateTime.fromMillisecondsSinceEpoch(event.occurredAt);
    return _isSameDay(time, day);
  }).firstOrNull;
  if (checkIn != null) return checkIn.cigarettes;
  if (profile.mode == QuitSmokingMode.immediate) return 0;
  final planStart = _dateOnly(DateTime.fromMillisecondsSinceEpoch(
    profile.planStartDate > 0
        ? profile.planStartDate
        : profile.stageStartDate > 0
            ? profile.stageStartDate
            : profile.targetDate,
  ));
  if (_dateOnly(day).isBefore(planStart)) {
    return profile.stageGoal > 0 ? profile.stageGoal : profile.dailyBaseline;
  }
  return buildGradualQuitPlan(profile).stageFor(day).target;
}

int? adaptiveStageToExtend({
  required QuitSmokingProfile profile,
  required Iterable<QuitSmokingEvent> events,
  required DateTime now,
}) {
  if (profile.mode != QuitSmokingMode.gradual || profile.needsReplan) {
    return null;
  }
  final plan = buildGradualQuitPlan(profile);
  final stage = plan.stageFor(now);
  if (stage.target == 0 || profile.extendedStageIndexes.contains(stage.index)) {
    return null;
  }
  return _hasTwoConsecutiveFailures(events, stage.start, _dateOnly(now))
      ? stage.index
      : null;
}

bool shouldSuggestGradualReplan({
  required QuitSmokingProfile profile,
  required Iterable<QuitSmokingEvent> events,
  required DateTime now,
}) {
  if (profile.mode != QuitSmokingMode.gradual || profile.needsReplan) {
    return false;
  }
  final plan = buildGradualQuitPlan(profile);
  final stage = plan.stageFor(now);
  final extensionCount = profile.extendedStageIndexes
      .where((index) => index == stage.index)
      .length;
  if (stage.target == 0 || extensionCount == 0) return false;
  final latestExtensionStart = stage.originalEnd.add(
    Duration(days: 1 + (extensionCount - 1) * 3),
  );
  return _hasTwoConsecutiveFailures(
    events,
    latestExtensionStart,
    _dateOnly(now),
  );
}

bool _hasTwoConsecutiveFailures(
  Iterable<QuitSmokingEvent> events,
  DateTime from,
  DateTime through,
) {
  final failedDays = events
      .where((event) =>
          event.type == QuitSmokingEventType.checkIn && event.success == false)
      .map((event) =>
          _dateOnly(DateTime.fromMillisecondsSinceEpoch(event.occurredAt)))
      .where((day) => !day.isBefore(from) && !day.isAfter(through))
      .toSet()
      .toList()
    ..sort();
  if (failedDays.length < 2) return false;
  return failedDays.last.difference(failedDays[failedDays.length - 2]).inDays ==
      1;
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

bool _isSameDay(DateTime first, DateTime second) =>
    first.year == second.year &&
    first.month == second.month &&
    first.day == second.day;

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
    required this.expectedCigarettes,
    required this.actualCigarettes,
    required this.avoidedCigarettesExact,
    required this.avoidedCigarettes,
    required this.savedMoney,
    required this.todaySavedMoney,
    required this.startedAt,
    required this.smokeFreeStartedAt,
  });

  final int smokeFreeDays;
  final int todayCount;
  final double expectedCigarettes;
  final int actualCigarettes;
  final double avoidedCigarettesExact;
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
      expectedCigarettes: 0,
      actualCigarettes: 0,
      avoidedCigarettesExact: 0,
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
  final elapsedDays =
      now.difference(start).inMilliseconds / Duration.millisecondsPerDay;
  final expectedSinceStart = profile.dailyBaseline * elapsedDays;
  final avoidedExact =
      (expectedSinceStart - actualSinceStart).clamp(0.0, 1000000.0).toDouble();
  final avoided = avoidedExact.floor();
  final savedMoney = profile.packCigarettes <= 0
      ? 0.0
      : avoidedExact / profile.packCigarettes * profile.packPrice;
  final todayElapsedDays =
      now.difference(today).inMilliseconds / Duration.millisecondsPerDay;
  final todayExpected = profile.dailyBaseline * todayElapsedDays;
  final todayAvoided =
      (todayExpected - todayCount).clamp(0.0, profile.dailyBaseline).toDouble();
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
    expectedCigarettes: expectedSinceStart,
    actualCigarettes: actualSinceStart,
    avoidedCigarettesExact: avoidedExact,
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

List<int> _asIntList(Object? value) =>
    value is List ? value.map(_asInt).whereType<int>().toList() : const [];
