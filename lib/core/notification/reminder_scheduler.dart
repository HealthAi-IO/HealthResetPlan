import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../data/health_models.dart';
import '../data/health_repository.dart';

/// 将 [HealthRepository] 中的提醒规则同步为系统本地通知。
///
/// 调用顺序：initialize() → requestPermission() → syncAll()
/// 每次新增或删除提醒后再调用一次 syncAll() 保持同步。
class ReminderScheduler {
  ReminderScheduler({required this.repository});

  final HealthRepository repository;
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  static const _channelId = 'hrp_reminders';
  static const _channelName = '健康提醒';
  static const _channelDesc = '饮食、运动、用药、称重、饮水定时提醒';

  bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux);

  // ── 初始化 ─────────────────────────────────────────────────

  Future<void> initialize() async {
    if (!_supported || _initialized) return;

    tz.initializeTimeZones();
    final tzInfo = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(tzInfo.identifier));

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const linux = LinuxInitializationSettings(defaultActionName: '打开健康重启计划');

    const settings = InitializationSettings(
      android: android,
      iOS: darwin,
      macOS: darwin,
      linux: linux,
    );

    await _plugin.initialize(settings);
    _initialized = true;
  }

  // ── 权限请求 ────────────────────────────────────────────────

  Future<void> requestPermission() async {
    if (!_supported || !_initialized) return;

    if (defaultTargetPlatform == TargetPlatform.android) {
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } else if (defaultTargetPlatform == TargetPlatform.macOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }
  }

  // ── 同步全部提醒 ─────────────────────────────────────────────

  /// 取消所有已调度通知，再根据数据库中的提醒规则重新调度。
  Future<void> syncAll() async {
    if (!_supported || !_initialized) return;

    await _plugin.cancelAll();

    final reminders = await repository.loadReminders();
    for (final reminder in reminders) {
      if (reminder.id != null) {
        await _scheduleDaily(reminder);
      }
    }
  }

  // ── 单条提醒调度 ─────────────────────────────────────────────

  Future<void> _scheduleDaily(ReminderData reminder) async {
    final time = reminder.remindTime;
    final now = tz.TZDateTime.now(tz.local);

    // 计算今日该时刻；若已过则推到明天
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    final note = reminder.payload['note'] as String? ?? '';
    final body = note.isNotEmpty ? note : reminder.label;

    await _plugin.zonedSchedule(
      reminder.id!,
      reminder.label,
      body,
      scheduled,
      _buildDetails(),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  NotificationDetails _buildDetails() {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: false,
        presentSound: true,
      ),
      macOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: false,
        presentSound: true,
      ),
      linux: LinuxNotificationDetails(),
    );
  }
}
