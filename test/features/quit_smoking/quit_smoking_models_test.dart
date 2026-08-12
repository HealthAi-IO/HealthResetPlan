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
}
