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

  test('累计节省按当天已过去时间逐步增长', () {
    final progress = calculateQuitSmokingProgress(
      profile: profile,
      events: const [],
      now: DateTime(2026, 8, 10, 12),
    );

    expect(progress.avoidedCigarettes, 5);
    expect(progress.expectedCigarettes, closeTo(5, 0.01));
    expect(progress.actualCigarettes, 0);
    expect(progress.avoidedCigarettesExact, closeTo(5, 0.01));
    expect(progress.savedMoney, closeTo(5, 0.01));
    expect(progress.todaySavedMoney, closeTo(5, 0.01));
  });

  test('累计节省会扣除实际记录的吸烟支数', () {
    final smokedAt = DateTime(2026, 8, 10, 10);
    final progress = calculateQuitSmokingProgress(
      profile: profile,
      events: [
        QuitSmokingEvent(
          type: QuitSmokingEventType.smoked,
          occurredAt: smokedAt.millisecondsSinceEpoch,
          cigarettes: 2,
          intensity: 0,
          success: null,
          trigger: '',
          strategy: '',
          note: '',
          createdAt: smokedAt.millisecondsSinceEpoch,
        ),
      ],
      now: DateTime(2026, 8, 10, 12),
    );

    expect(progress.avoidedCigarettes, 3);
    expect(progress.expectedCigarettes, closeTo(5, 0.01));
    expect(progress.actualCigarettes, 2);
    expect(progress.avoidedCigarettesExact, closeTo(3, 0.01));
    expect(progress.savedMoney, closeTo(3, 0.01));
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

  group('自动渐进计划', () {
    QuitSmokingProfile gradualProfile({
      List<int> extensions = const [],
      bool needsReplan = false,
    }) {
      final planStart = DateTime(2026, 8, 22);
      return QuitSmokingProfile(
        mode: QuitSmokingMode.gradual,
        dailyBaseline: 20,
        packCigarettes: 20,
        packPrice: 25,
        smokingYears: 10,
        targetDate: DateTime(2026, 9, 4).millisecondsSinceEpoch,
        motivation: '',
        triggers: const [],
        stageGoal: 20,
        stageStartDate: planStart.millisecondsSinceEpoch,
        planDurationDays: 14,
        planStartTarget: 20,
        extendedStageIndexes: extensions,
        needsReplan: needsReplan,
        remindersEnabled: false,
        createdAt: planStart.millisecondsSinceEpoch,
        updatedAt: planStart.millisecondsSinceEpoch,
      );
    }

    QuitSmokingEvent failedCheckIn(DateTime day, int target) =>
        QuitSmokingEvent(
          type: QuitSmokingEventType.checkIn,
          occurredAt: day.millisecondsSinceEpoch,
          cigarettes: target,
          intensity: 0,
          success: false,
          trigger: '',
          strategy: '',
          note: '',
          createdAt: day.millisecondsSinceEpoch,
        );

    test('14 天计划从 20 支自动生成 15、10、5、0', () {
      final plan = buildGradualQuitPlan(gradualProfile());

      expect(plan.stages.map((stage) => stage.target), [15, 10, 5, 0]);
      expect(plan.stages.first.start, DateTime(2026, 8, 22));
      expect(plan.stages.first.end, DateTime(2026, 8, 25));
      expect(plan.quitDate, DateTime(2026, 9, 4));
    });

    test('阶段延长三天后后续阶段和完全戒烟日同步顺延', () {
      final plan = buildGradualQuitPlan(gradualProfile(extensions: [0]));

      expect(plan.stages.first.end, DateTime(2026, 8, 28));
      expect(plan.stages[1].start, DateTime(2026, 8, 29));
      expect(plan.quitDate, DateTime(2026, 9, 7));
    });

    test('同一阶段连续两天未达标会触发一次自动延长', () {
      final profile = gradualProfile();
      final events = [
        failedCheckIn(DateTime(2026, 8, 22, 20), 15),
        failedCheckIn(DateTime(2026, 8, 23, 20), 15),
      ];

      expect(
        adaptiveStageToExtend(
          profile: profile,
          events: events,
          now: DateTime(2026, 8, 23, 21),
        ),
        0,
      );
      expect(
        adaptiveStageToExtend(
          profile: gradualProfile(extensions: [0]),
          events: events,
          now: DateTime(2026, 8, 23, 21),
        ),
        isNull,
      );
    });

    test('延长区间再次连续两天未达标会建议重新规划', () {
      final events = [
        failedCheckIn(DateTime(2026, 8, 26, 20), 15),
        failedCheckIn(DateTime(2026, 8, 27, 20), 15),
      ];

      expect(
        shouldSuggestGradualReplan(
          profile: gradualProfile(extensions: [0]),
          events: events,
          now: DateTime(2026, 8, 27, 21),
        ),
        isTrue,
      );
    });

    test('历史打卡保存的目标优先于后来调整的计划', () {
      final day = DateTime(2026, 8, 26);
      final checkIn = QuitSmokingEvent(
        type: QuitSmokingEventType.checkIn,
        occurredAt: day.millisecondsSinceEpoch,
        cigarettes: 12,
        intensity: 0,
        success: true,
        trigger: '',
        strategy: '',
        note: '',
        createdAt: day.millisecondsSinceEpoch,
      );

      expect(
        quitSmokingTargetForDay(
          profile: gradualProfile(),
          events: [checkIn],
          day: day,
        ),
        12,
      );
    });

    test('重新规划不会改变累计节省的统计起点', () {
      final profile = gradualProfile().copyWith(
        stageStartDate: DateTime(2026, 8, 10).millisecondsSinceEpoch,
        planStartDate: DateTime(2026, 8, 22).millisecondsSinceEpoch,
      );

      final progress = calculateQuitSmokingProgress(
        profile: profile,
        events: const [],
        now: DateTime(2026, 8, 23),
      );

      expect(progress.expectedCigarettes, 260);
      expect(buildGradualQuitPlan(profile).stages.first.start,
          DateTime(2026, 8, 22));
    });
  });
}
