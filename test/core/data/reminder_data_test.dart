import 'package:flutter_test/flutter_test.dart';
import 'package:health_reset_plan/core/data/health_models.dart';

void main() {
  test('用药提醒可以读取对应时间点的延后状态', () {
    final occurrence = DateTime(2026, 9, 22, 8);
    final reminder = ReminderData(
      id: 1,
      type: 'medicine',
      remindAt: occurrence.millisecondsSinceEpoch,
      payload: {
        'dailyTimes': const [
          {'hour': 8, 'minute': 0},
        ],
        'snoozeHistory': {
          '2026-09-22 08:00':
              DateTime(2026, 9, 22, 8, 10).millisecondsSinceEpoch,
        },
      },
      channel: 'local',
      status: 'pending',
      createdAt: occurrence.millisecondsSinceEpoch,
      updatedAt: occurrence.millisecondsSinceEpoch,
    );

    expect(reminder.snoozeAt(occurrence), DateTime(2026, 9, 22, 8, 10));
    expect(reminder.snoozeAt(DateTime(2026, 9, 22, 20)), isNull);
  });
}
