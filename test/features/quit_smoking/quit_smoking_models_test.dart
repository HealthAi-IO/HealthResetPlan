import 'package:flutter_test/flutter_test.dart';
import 'package:health_reset_plan/features/quit_smoking/quit_smoking_models.dart';

void main() {
  final start = DateTime(2026, 8, 10, 8);
  final profile = QuitSmokingProfile(
    mode: QuitSmokingMode.immediate,
    dailyBaseline: 10,
    packCigarettes: 20,
    packPrice: 20,
    smokingYears: 5,
    targetDate: start.millisecondsSinceEpoch,
    motivation: '',
    triggers: const [],
    stageGoal: 0,
    stageStartDate: start.millisecondsSinceEpoch,
    remindersEnabled: false,
    createdAt: start.millisecondsSinceEpoch,
    updatedAt: start.millisecondsSinceEpoch,
  );

  test('没有吸烟记录时从计划开始计时', () {
    final progress = calculateQuitSmokingProgress(
      profile: profile,
      events: const [],
      now: DateTime(2026, 8, 11, 8),
    );

    expect(progress.smokeFreeStartedAt, start);
    expect(progress.smokeFreeDays, 1);
  });

  test('吸烟后从最后一次吸烟重新计时', () {
    final lastSmoke = DateTime(2026, 8, 11, 7, 30);
    final progress = calculateQuitSmokingProgress(
      profile: profile,
      events: [
        QuitSmokingEvent(
          type: QuitSmokingEventType.smoked,
          occurredAt: lastSmoke.millisecondsSinceEpoch,
          cigarettes: 1,
          intensity: 0,
          success: null,
          trigger: '',
          strategy: '',
          note: '',
          createdAt: lastSmoke.millisecondsSinceEpoch,
        ),
      ],
      now: DateTime(2026, 8, 11, 8),
    );

    expect(progress.smokeFreeStartedAt, lastSmoke);
    expect(progress.smokeFreeDays, 0);
  });

  test('连续打卡只统计截至当天不中断的日期', () {
    QuitSmokingEvent checkIn(DateTime day) => QuitSmokingEvent(
          type: QuitSmokingEventType.checkIn,
          occurredAt: day.millisecondsSinceEpoch,
          cigarettes: 0,
          intensity: 0,
          success: true,
          trigger: '',
          strategy: '',
          note: '',
          createdAt: day.millisecondsSinceEpoch,
        );

    final streak = calculateCheckInStreak(
      events: [
        checkIn(DateTime(2026, 8, 14, 20)),
        checkIn(DateTime(2026, 8, 13, 20)),
        checkIn(DateTime(2026, 8, 11, 20)),
      ],
      through: DateTime(2026, 8, 14, 21),
    );

    expect(streak, 2);
  });

  test('未达标的总结不会计入连续达标天数', () {
    QuitSmokingEvent checkIn(DateTime day, bool success) => QuitSmokingEvent(
          type: QuitSmokingEventType.checkIn,
          occurredAt: day.millisecondsSinceEpoch,
          cigarettes: 0,
          intensity: 0,
          success: success,
          trigger: '',
          strategy: '',
          note: '',
          createdAt: day.millisecondsSinceEpoch,
        );

    final streak = calculateCheckInStreak(
      events: [
        checkIn(DateTime(2026, 8, 14, 20), false),
        checkIn(DateTime(2026, 8, 13, 20), true),
      ],
      through: DateTime(2026, 8, 14, 21),
    );

    expect(streak, 0);
  });

  test('总结后新增当天吸烟记录会使总结失效', () {
    final checkInTime = DateTime(2026, 8, 14, 9, 29);
    final checkIn = QuitSmokingEvent(
      type: QuitSmokingEventType.checkIn,
      occurredAt: checkInTime.millisecondsSinceEpoch,
      cigarettes: 0,
      intensity: 0,
      success: true,
      trigger: '',
      strategy: '',
      note: '',
      createdAt: checkInTime.millisecondsSinceEpoch,
    );
    final smokedAt = DateTime(2026, 8, 14, 11, 48);
    final smoked = QuitSmokingEvent(
      type: QuitSmokingEventType.smoked,
      occurredAt: smokedAt.millisecondsSinceEpoch,
      cigarettes: 1,
      intensity: 0,
      success: null,
      trigger: '',
      strategy: '',
      note: '',
      createdAt: smokedAt.millisecondsSinceEpoch,
    );

    expect(
      shouldInvalidateCheckIn(checkIn: checkIn, events: [checkIn, smoked]),
      isTrue,
    );
  });

  test('其他日期或总结前创建的吸烟记录不会使总结失效', () {
    final checkInTime = DateTime(2026, 8, 14, 20);
    final checkIn = QuitSmokingEvent(
      type: QuitSmokingEventType.checkIn,
      occurredAt: checkInTime.millisecondsSinceEpoch,
      cigarettes: 0,
      intensity: 0,
      success: true,
      trigger: '',
      strategy: '',
      note: '',
      createdAt: checkInTime.millisecondsSinceEpoch,
    );
    QuitSmokingEvent smoked(DateTime occurredAt, DateTime createdAt) =>
        QuitSmokingEvent(
          type: QuitSmokingEventType.smoked,
          occurredAt: occurredAt.millisecondsSinceEpoch,
          cigarettes: 1,
          intensity: 0,
          success: null,
          trigger: '',
          strategy: '',
          note: '',
          createdAt: createdAt.millisecondsSinceEpoch,
        );

    expect(
      shouldInvalidateCheckIn(
        checkIn: checkIn,
        events: [
          smoked(DateTime(2026, 8, 13, 21), DateTime(2026, 8, 14, 21)),
          smoked(DateTime(2026, 8, 14, 8), DateTime(2026, 8, 14, 8)),
        ],
      ),
      isFalse,
    );
  });
}
