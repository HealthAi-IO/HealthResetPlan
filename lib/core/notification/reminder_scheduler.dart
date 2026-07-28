import 'dart:async';

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
  Timer? _inAppReminderTimer;
  final Set<String> _inAppReminderKeys = <String>{};
  final StreamController<ReminderData> _inAppReminderController =
      StreamController<ReminderData>.broadcast();

  static const _channelId = 'hrp_reminders';
  static const _channelName = '健康提醒';
  static const _channelDesc = '饮食、运动、用药、称重、饮水定时提醒';

  Stream<ReminderData> get reminderEvents => _inAppReminderController.stream;

  bool get _usesInAppReminders =>
      kIsWeb || defaultTargetPlatform == TargetPlatform.windows;

  bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux);

  // ── 初始化 ─────────────────────────────────────────────────

  Future<void> initialize() async {
    if (_initialized) return;
    if (_usesInAppReminders) {
      _initialized = true;
      _startInAppReminderLoop();
      return;
    }
    if (!_supported) return;

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
    if (!_initialized) return;
    if (_usesInAppReminders) {
      _startInAppReminderLoop();
      await _checkInAppReminders();
      return;
    }
    if (!_supported) return;

    await _plugin.cancelAll();

    final reminders = await repository.loadReminders();
    final now = tz.TZDateTime.now(tz.local);
    for (final reminder in reminders) {
      if (reminder.id == null) continue;
      await _scheduleUpcoming(reminder, now);
    }
  }

  // ── 单条提醒调度 ─────────────────────────────────────────────

  Future<void> _scheduleUpcoming(
    ReminderData reminder,
    tz.TZDateTime now,
  ) async {
    final reminderDate = reminder.remindTime;
    final isLocalRule = reminder.channel == 'local';

    if (isLocalRule) {
      var next = tz.TZDateTime(
        now.location,
        now.year,
        now.month,
        now.day,
        reminderDate.hour,
        reminderDate.minute,
      );
      if (!next.isAfter(now)) {
        next = next.add(const Duration(days: 1));
      }
      await _scheduleOnce(
        reminder,
        next,
        0,
        matchDateTimeComponents: DateTimeComponents.time,
      );
      return;
    }

    final scheduled = tz.TZDateTime.from(reminderDate, now.location);
    if (scheduled.isBefore(now) ||
        scheduled.isAfter(now.add(const Duration(days: 7)))) {
      return;
    }
    await _scheduleOnce(reminder, scheduled, 0);
  }

  Future<void> _scheduleOnce(
    ReminderData reminder,
    tz.TZDateTime scheduled,
    int dayOffset, {
    DateTimeComponents? matchDateTimeComponents,
  }) async {
    final note = reminder.payload['note'] as String? ?? '';
    final body = note.isNotEmpty ? note : reminder.label;

    await _plugin.zonedSchedule(
      reminder.id! * 10 + dayOffset,
      reminder.label,
      body,
      scheduled,
      _buildDetails(),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: matchDateTimeComponents,
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

  void _startInAppReminderLoop() {
    _inAppReminderTimer ??= Timer.periodic(
      const Duration(minutes: 1),
      (_) => _checkInAppReminders(),
    );
  }

  Future<void> _checkInAppReminders() async {
    final now = DateTime.now();
    final reminders = await repository.loadReminders();
    for (final reminder in reminders) {
      final time = reminder.remindTime;
      if (time.hour != now.hour || time.minute != now.minute) continue;
      if (reminder.channel != 'local' &&
          (time.year != now.year ||
              time.month != now.month ||
              time.day != now.day)) {
        continue;
      }

      final id = reminder.id?.toString() ??
          '${reminder.type}-${time.hour}-${time.minute}';
      final key = '${now.year}-${now.month}-${now.day}-$id';
      if (!_inAppReminderKeys.add(key)) continue;

      _inAppReminderController.add(reminder);
    }
  }
}
