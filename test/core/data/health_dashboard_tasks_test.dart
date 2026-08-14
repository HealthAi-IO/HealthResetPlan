import 'package:flutter_test/flutter_test.dart';
import 'package:health_reset_plan/core/data/health_models.dart';

void main() {
  test('今日完成率按实际任务数量计算', () {
    final now = DateTime.now();
    final data = HealthDashboardData(
      profile: null,
      indicators: const [],
      plans: [
        PlanRecordData(
          type: 'exercise',
          planDate: now.millisecondsSinceEpoch,
          payload: const {},
          aiProvider: 'local',
          aiModel: 'rules',
          createdAt: now.millisecondsSinceEpoch,
          updatedAt: now.millisecondsSinceEpoch,
        ),
      ],
      clockRecords: [
        ClockRecordData(
          type: 'meal',
          status: 'done',
          clockAt: now.millisecondsSinceEpoch,
          note: '',
          photoPath: '',
          createdAt: now.millisecondsSinceEpoch,
          updatedAt: now.millisecondsSinceEpoch,
        ),
      ],
      reminders: const [],
    );

    expect(data.todayTaskTypes(), {'meal', 'weight', 'exercise'});
    expect(data.todayCompletion, closeTo(1 / 3, 0.001));
  });

  test('跳过任务不会增加完成率', () {
    final now = DateTime.now().millisecondsSinceEpoch;
    final data = HealthDashboardData(
      profile: null,
      indicators: const [],
      plans: const [],
      clockRecords: [
        ClockRecordData(
          type: 'weight',
          status: 'skip',
          clockAt: now,
          note: '',
          photoPath: '',
          createdAt: now,
          updatedAt: now,
        ),
      ],
      reminders: const [],
    );

    expect(data.todayTaskTypes(), {'meal', 'weight'});
    expect(data.todayCompletion, 0);
  });
}
