import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_reset_plan/core/data/health_models.dart';
import 'package:health_reset_plan/core/data/health_repository.dart';
import 'package:health_reset_plan/core/network/api_client.dart';
import 'package:health_reset_plan/core/network/online_data_api.dart';
import 'package:health_reset_plan/core/notification/reminder_scheduler.dart';
import 'package:health_reset_plan/core/storage/app_database.dart';

final _due = DateTime(2026, 11, 2, 12, 46);

ReminderData _reminder(
        {int id = 1,
        String status = 'pending',
        String mode = 'once',
        String type = 'water',
        DateTime? time}) =>
    ReminderData(
      id: id,
      type: type,
      remindAt: (time ?? _due).millisecondsSinceEpoch,
      payload: {
        'scheduleMode': mode,
        'weekdays': [1]
      },
      channel: 'local',
      status: status,
      createdAt: _due.millisecondsSinceEpoch,
      updatedAt: _due.millisecondsSinceEpoch,
    );

void main() {
  test('单次提醒到点及当天结束前保留，次日零点清理，周提醒不删除', () async {
    final database = AppDatabase.instance;
    await database.switchSpace('reminder-retention-test');
    await database.bindOnline(_ReminderApi([
      _reminder(),
      _reminder(id: 2, type: 'medicine'),
      _reminder(id: 3, mode: 'weekly'),
    ]));
    addTearDown(database.unbindOnline);
    final repository = HealthRepository(database: database);

    expect(
        await repository
            .cleanupExpiredOnceReminders(_due.add(const Duration(seconds: 1))),
        isEmpty);
    expect(
        await repository
            .cleanupExpiredOnceReminders(DateTime(2026, 11, 2, 23, 59, 59)),
        isEmpty);
    expect(await repository.loadReminders(), hasLength(3));
    final removed =
        await repository.cleanupExpiredOnceReminders(DateTime(2026, 11, 3));
    expect(removed.map((item) => item.id), unorderedEquals([1, 2]));
    expect((await repository.loadReminders()).single.id, 3);
  });

  test('重新同步保留当天已到点但尚未投递的单次普通通知', () {
    final request = PendingNotificationRequest(
        1000, '提醒', '', 'reminder:1:${_due.millisecondsSinceEpoch}');
    expect(shouldKeepDueReminder(request, [_reminder()], _due), isTrue);
    expect(
        shouldKeepDueReminder(
            request, [_reminder()], _due.add(const Duration(minutes: 5))),
        isTrue);
    expect(shouldKeepDueReminder(request, [], _due), isFalse);
    expect(shouldKeepDueReminder(request, [_reminder(status: 'paused')], _due),
        isFalse);
    expect(
        shouldKeepDueReminder(request,
            [_reminder(time: _due.add(const Duration(minutes: 10)))], _due),
        isFalse);
    expect(
        shouldKeepDueReminder(
            request, [_reminder()], _due.subtract(const Duration(seconds: 1))),
        isFalse);
    expect(shouldKeepDueReminder(request, [_reminder()], DateTime(2026, 11, 3)),
        isFalse);
    expect(
        shouldKeepDueReminder(
            const PendingNotificationRequest(1000, '', '', 'invalid'),
            [_reminder()],
            _due),
        isFalse);
  });
}

class _ReminderApi extends OnlineDataApi {
  _ReminderApi(this.reminders) : super(client: ApiClient());
  final List<ReminderData> reminders;

  @override
  Future<OnlineDataSnapshot> load() async => OnlineDataSnapshot(
      version: 0,
      tables: {'reminder': reminders.map((item) => item.toRow()..['id'] = item.id).toList()});

  @override
  Future<OnlineDataSnapshot> save(
          int version, Map<String, List<Map<String, Object?>>> tables) async =>
      OnlineDataSnapshot(version: version + 1, tables: tables);
}
