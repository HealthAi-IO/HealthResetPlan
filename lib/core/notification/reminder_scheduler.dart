import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../data/health_models.dart';
import '../data/health_repository.dart';
import 'web_push_service.dart';

/// 将 [HealthRepository] 中的提醒规则同步为系统本地通知。
///
/// 调用顺序：initialize() → requestPermission() → syncAll()
/// 每次新增或删除提醒后再调用一次 syncAll() 保持同步。
class ReminderScheduler {
  ReminderScheduler({required this.repository, required this.webPushService});

  final HealthRepository repository;
  final WebPushService webPushService;
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  Timer? _inAppReminderTimer;
  final Set<String> _inAppReminderKeys = <String>{};
  final StreamController<ReminderData> _inAppReminderController =
      StreamController<ReminderData>.broadcast();
  final StreamController<int> _notificationTapController =
      StreamController<int>.broadcast();
  int? _pendingNotificationReminderId;

  static const _dailyChannelId = 'hrp_daily_reminders_v2';
  static const _dailyChannelName = '每日健康提醒';
  static const _dailyChannelDesc = '每日饮食、运动、用药、称重和饮水提醒';
  static const _planChannelId = 'hrp_plan_reminders_v2';
  static const _planChannelName = '计划提醒';
  static const _planChannelDesc = '健康计划临时提醒';
  static const _consentKey = 'reminder_user_consent';

  Stream<ReminderData> get reminderEvents => _inAppReminderController.stream;
  Stream<int> get notificationTapEvents => _notificationTapController.stream;

  Future<bool> hasUserConsent() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_consentKey) == true;
  }

  Future<void> grantUserConsent() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_consentKey, true);
  }

  int? takePendingNotificationReminderId() {
    final value = _pendingNotificationReminderId;
    _pendingNotificationReminderId = null;
    return value;
  }

  bool get _usesInAppReminders => kIsWeb;

  bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.windows);

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

    const android = AndroidInitializationSettings('notification_icon');
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const linux = LinuxInitializationSettings(defaultActionName: '打开健康重启计划');
    const windows = WindowsInitializationSettings(
      appName: '健康重启计划',
      appUserModelId: 'BeijingWeilingji.HealthResetPlan',
      guid: '9f20e3a4-5f3e-4f6d-8c72-7a82c02f8cb1',
    );

    const settings = InitializationSettings(
      android: android,
      iOS: darwin,
      macOS: darwin,
      linux: linux,
      windows: windows,
    );

    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: _handleNotificationResponse,
    );
    if (defaultTargetPlatform == TargetPlatform.android) {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _dailyChannelId,
          _dailyChannelName,
          description: _dailyChannelDesc,
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
        ),
      );
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _planChannelId,
          _planChannelName,
          description: _planChannelDesc,
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
        ),
      );
    }
    _initialized = true;
    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    final launchResponse = launchDetails?.notificationResponse;
    if (launchDetails?.didNotificationLaunchApp == true &&
        launchResponse != null) {
      _handleNotificationResponse(launchResponse);
    }
  }

  // ── 权限请求 ────────────────────────────────────────────────

  Future<bool?> requestPermission() async {
    if (kIsWeb) return webPushService.enable();
    if (!_supported || !_initialized) return true;

    if (defaultTargetPlatform == TargetPlatform.android) {
      return _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      return _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } else if (defaultTargetPlatform == TargetPlatform.macOS) {
      return _plugin
          .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }
    return true;
  }

  Future<bool?> notificationsEnabled() async {
    if (kIsWeb) return webPushService.isEnabled();
    if (!_supported) return true;
    if (!_initialized) await initialize();
    if (defaultTargetPlatform == TargetPlatform.android) {
      return _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.areNotificationsEnabled();
    }
    return null;
  }

  // ── 同步全部提醒 ─────────────────────────────────────────────

  /// 取消所有已调度通知，再根据数据库中的提醒规则重新调度。
  Future<void> syncAll() async {
    if (!_initialized) return;
    if (!await hasUserConsent()) {
      if (_supported) await _plugin.cancelAll();
      return;
    }
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
      if (reminder.id == null || !reminder.isEnabled) continue;
      await _scheduleUpcoming(reminder, now);
    }
  }

  Future<void> syncReminder(ReminderData reminder) async {
    if (!_initialized) await initialize();
    if (reminder.id == null) return;
    if (_usesInAppReminders) {
      _startInAppReminderLoop();
      return;
    }
    if (!_supported || !await hasUserConsent()) return;
    await _cancelReminderNotifications(reminder.id!);
    if (!reminder.isEnabled) return;
    await _scheduleUpcoming(reminder, tz.TZDateTime.now(tz.local));
  }

  Future<void> cancelReminder(int reminderId) async {
    if (!_initialized) await initialize();
    if (!_supported) return;
    await _cancelReminderNotifications(reminderId);
  }

  Future<void> _cancelReminderNotifications(int reminderId) async {
    for (var suffix = 0; suffix <= 7; suffix++) {
      await _plugin.cancel(id: reminderId * 10 + suffix);
    }
  }

  // ── 单条提醒调度 ─────────────────────────────────────────────

  Future<void> _scheduleUpcoming(
    ReminderData reminder,
    tz.TZDateTime now,
  ) async {
    if (reminder.isWeekly) {
      for (final weekday in reminder.weekdays) {
        final scheduled = _nextWeekdayOccurrence(reminder, weekday, now);
        if (scheduled == null) continue;
        await _scheduleOnce(
          reminder,
          scheduled,
          weekday,
          matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        );
      }
      return;
    }

    final scheduled = tz.TZDateTime.from(reminder.remindTime, now.location);
    if (!scheduled.isAfter(now)) return;
    if (reminder.channel != 'local' &&
        scheduled.isAfter(now.add(const Duration(days: 7)))) {
      return;
    }
    await _scheduleOnce(reminder, scheduled, 0);
  }

  tz.TZDateTime? _nextWeekdayOccurrence(
    ReminderData reminder,
    int weekday,
    tz.TZDateTime now,
  ) {
    final today = DateTime(now.year, now.month, now.day);
    final firstDay =
        reminder.startDate.isAfter(today) ? reminder.startDate : today;
    for (var offset = 0; offset < 14; offset++) {
      final day = firstDay.add(Duration(days: offset));
      if (day.weekday != weekday || !reminder.occursOn(day)) continue;
      final scheduled = tz.TZDateTime(
        now.location,
        day.year,
        day.month,
        day.day,
        reminder.remindTime.hour,
        reminder.remindTime.minute,
      );
      if (scheduled.isAfter(now)) return scheduled;
    }
    return null;
  }

  Future<void> _scheduleOnce(
    ReminderData reminder,
    tz.TZDateTime scheduled,
    int dayOffset, {
    DateTimeComponents? matchDateTimeComponents,
  }) async {
    await _plugin.zonedSchedule(
      id: reminder.id! * 10 + dayOffset,
      title: '健康重启计划提醒',
      body: '你有一项已设定的健康提醒',
      scheduledDate: scheduled,
      notificationDetails: _buildDetails(reminder),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: matchDateTimeComponents,
      payload: 'reminder:${reminder.id}',
    );
  }

  void _handleNotificationResponse(NotificationResponse response) {
    final payload = response.payload ?? '';
    if (!payload.startsWith('reminder:')) return;
    final reminderId = int.tryParse(payload.substring('reminder:'.length));
    if (reminderId == null) return;
    if (_notificationTapController.hasListener) {
      _notificationTapController.add(reminderId);
    } else {
      _pendingNotificationReminderId = reminderId;
    }
  }

  NotificationDetails _buildDetails(ReminderData reminder) {
    final android = reminder.channel == 'local'
        ? const AndroidNotificationDetails(
            _dailyChannelId,
            _dailyChannelName,
            channelDescription: _dailyChannelDesc,
            importance: Importance.high,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
            category: AndroidNotificationCategory.reminder,
            visibility: NotificationVisibility.private,
          )
        : const AndroidNotificationDetails(
            _planChannelId,
            _planChannelName,
            channelDescription: _planChannelDesc,
            importance: Importance.high,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
            category: AndroidNotificationCategory.reminder,
            visibility: NotificationVisibility.private,
          );
    return NotificationDetails(
      android: android,
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
      windows: const WindowsNotificationDetails(
        scenario: WindowsNotificationScenario.reminder,
      ),
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
      if (!reminder.isEnabled) continue;
      final time = reminder.remindTime;
      if (time.hour != now.hour || time.minute != now.minute) continue;
      if (!reminder.occursOn(now)) continue;

      final id = reminder.id?.toString() ??
          '${reminder.type}-${time.hour}-${time.minute}';
      final key = '${now.year}-${now.month}-${now.day}-$id';
      if (!_inAppReminderKeys.add(key)) continue;

      _inAppReminderController.add(reminder);
    }
  }
}
