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

class MedicationNotificationAction {
  const MedicationNotificationAction(
    this.reminderId,
    this.action,
    this.scheduledAt,
  );

  final int reminderId;
  final String action;
  final DateTime? scheduledAt;
}

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
  final StreamController<MedicationNotificationAction>
      _medicationActionController =
      StreamController<MedicationNotificationAction>.broadcast();
  int? _pendingNotificationReminderId;
  MedicationNotificationAction? _pendingMedicationAction;

  static const _dailyChannelId = 'hrp_daily_reminders_v2';
  static const _dailyChannelName = '每日健康提醒';
  static const _dailyChannelDesc = '每日饮食、运动、用药、称重和饮水提醒';
  static const _planChannelId = 'hrp_plan_reminders_v2';
  static const _planChannelName = '计划提醒';
  static const _planChannelDesc = '健康计划临时提醒';
  static const _consentKey = 'reminder_user_consent';

  Stream<ReminderData> get reminderEvents => _inAppReminderController.stream;
  Stream<int> get notificationTapEvents => _notificationTapController.stream;
  Stream<MedicationNotificationAction> get medicationActionEvents =>
      _medicationActionController.stream;

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

  MedicationNotificationAction? takePendingMedicationAction() {
    final value = _pendingMedicationAction;
    _pendingMedicationAction = null;
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

  Future<bool> ensureExactAlarmPermission() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return true;
    if (!_initialized) await initialize();
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (await androidPlugin?.canScheduleExactNotifications() == true) {
      return true;
    }
    await androidPlugin?.requestExactAlarmsPermission();
    return await androidPlugin?.canScheduleExactNotifications() == true;
  }

  Future<bool?> exactAlarmEnabled() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    if (!_initialized) await initialize();
    return _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.canScheduleExactNotifications();
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
    final medicationGroups = <int, List<_MedicationOccurrence>>{};
    for (final reminder in reminders) {
      if (reminder.id == null || !reminder.isEnabled) continue;
      if (reminder.type == 'medicine') {
        for (final occurrence in _medicationOccurrences(reminder, now)) {
          medicationGroups
              .putIfAbsent(
                occurrence.scheduled.millisecondsSinceEpoch,
                () => <_MedicationOccurrence>[],
              )
              .add(occurrence);
        }
      } else {
        await _scheduleUpcoming(reminder, now);
      }
    }
    for (final group in medicationGroups.values) {
      await _scheduleMedicationGroup(group);
    }
  }

  Future<void> syncReminder(ReminderData reminder) async {
    if (reminder.id == null) return;
    await syncAll();
  }

  Future<void> cancelReminder(int reminderId) async {
    if (!_initialized) await initialize();
    if (!_supported) return;
    await syncAll();
  }

  List<_MedicationOccurrence> _medicationOccurrences(
    ReminderData reminder,
    tz.TZDateTime now,
  ) {
    final occurrences = <_MedicationOccurrence>[];
    final today = DateTime(now.year, now.month, now.day);
    for (var dayOffset = 0; dayOffset < 8; dayOffset++) {
      final day = today.add(Duration(days: dayOffset));
      if (!reminder.occursOn(day)) continue;
      for (final time in reminder.dailyTimes) {
        final scheduled = tz.TZDateTime(
          now.location,
          day.year,
          day.month,
          day.day,
          time.hour,
          time.minute,
        );
        if (!scheduled.isAfter(now)) continue;
        final localScheduled = DateTime(
          scheduled.year,
          scheduled.month,
          scheduled.day,
          scheduled.hour,
          scheduled.minute,
        );
        if (reminder.actionAt(localScheduled) != null) continue;
        occurrences.add(_MedicationOccurrence(
          reminder: reminder,
          time: time,
          scheduled: scheduled,
        ));
      }
    }
    return occurrences;
  }

  Future<void> _scheduleMedicationGroup(
    List<_MedicationOccurrence> group,
  ) async {
    if (group.isEmpty) return;
    final first = group.first;
    final scheduled = first.scheduled;
    final minuteKey = scheduled.millisecondsSinceEpoch ~/ 60000;
    final notificationId = 1200000000 + (minuteKey % 400000000) * 2;
    final multiple = group.length > 1;
    final names = group
        .map((item) => item.reminder.displayLabel)
        .toSet()
        .take(3)
        .join('、');
    final title = multiple
        ? '用药提醒 · 共 ${group.length} 种药'
        : '${first.reminder.displayLabel}用药提醒';
    final body = multiple
        ? '$names，请打开 APP 逐项确认'
        : _medicineNotificationBody(first.reminder, first.time);
    final payload = multiple
        ? 'medicine-group:${scheduled.millisecondsSinceEpoch}'
        : 'reminder:${first.reminder.id}:${scheduled.millisecondsSinceEpoch}';
    await _plugin.zonedSchedule(
      id: notificationId,
      title: title,
      body: body,
      scheduledDate: scheduled,
      notificationDetails: _buildDetails(
        first.reminder,
        includeMedicineActions: !multiple,
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: payload,
    );
    await _plugin.zonedSchedule(
      id: notificationId + 1,
      title: multiple
          ? '${group.length} 种药尚未全部确认'
          : '${first.reminder.displayLabel}尚未确认',
      body: multiple ? '请打开 APP 查看每种药的服用状态。' : '如已服用请及时记录；如未服用，请遵循医嘱处理。',
      scheduledDate: scheduled.add(const Duration(minutes: 30)),
      notificationDetails: _buildDetails(
        first.reminder,
        includeMedicineActions: !multiple,
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: payload,
    );
  }

  // ── 单条提醒调度 ─────────────────────────────────────────────

  Future<void> _scheduleUpcoming(
    ReminderData reminder,
    tz.TZDateTime now,
  ) async {
    if (reminder.isWeekly) {
      for (var timeIndex = 0;
          timeIndex < reminder.dailyTimes.length;
          timeIndex++) {
        final time = reminder.dailyTimes[timeIndex];
        for (final weekday in reminder.weekdays) {
          final scheduled =
              _nextWeekdayOccurrence(reminder, weekday, time, now);
          if (scheduled == null) continue;
          await _scheduleOnce(
            reminder,
            scheduled,
            weekday,
            timeIndex: timeIndex,
            matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
          );
        }
      }
      return;
    }

    for (var timeIndex = 0;
        timeIndex < reminder.dailyTimes.length;
        timeIndex++) {
      final time = reminder.dailyTimes[timeIndex];
      final scheduled = tz.TZDateTime(
        now.location,
        reminder.remindTime.year,
        reminder.remindTime.month,
        reminder.remindTime.day,
        time.hour,
        time.minute,
      );
      if (!scheduled.isAfter(now)) continue;
      final localScheduled = DateTime(
        scheduled.year,
        scheduled.month,
        scheduled.day,
        scheduled.hour,
        scheduled.minute,
      );
      if (reminder.actionAt(localScheduled) != null ||
          reminder.acknowledgedAt(localScheduled)) {
        continue;
      }
      if (reminder.channel != 'local' &&
          scheduled.isAfter(now.add(const Duration(days: 7)))) {
        continue;
      }
      await _scheduleOnce(reminder, scheduled, 0, timeIndex: timeIndex);
    }
  }

  tz.TZDateTime? _nextWeekdayOccurrence(
    ReminderData reminder,
    int weekday,
    TimeOfDayValue time,
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
        time.hour,
        time.minute,
      );
      final localScheduled = DateTime(
        scheduled.year,
        scheduled.month,
        scheduled.day,
        scheduled.hour,
        scheduled.minute,
      );
      if (scheduled.isAfter(now) &&
          reminder.actionAt(localScheduled) == null &&
          !reminder.acknowledgedAt(localScheduled)) {
        return scheduled;
      }
    }
    return null;
  }

  Future<void> _scheduleOnce(
    ReminderData reminder,
    tz.TZDateTime scheduled,
    int dayOffset, {
    int timeIndex = 0,
    DateTimeComponents? matchDateTimeComponents,
  }) async {
    final notificationId = reminder.id! * 1000 + timeIndex * 20 + dayOffset;
    await _plugin.zonedSchedule(
      id: notificationId,
      title: reminder.type == 'medicine'
          ? '${reminder.displayLabel}用药提醒'
          : '健康重启计划提醒',
      body: reminder.type == 'medicine'
          ? _medicineNotificationBody(reminder)
          : '你有一项已设定的健康提醒',
      scheduledDate: scheduled,
      notificationDetails: _buildDetails(reminder),
      androidScheduleMode: reminder.type == 'medicine'
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: matchDateTimeComponents,
      payload: 'reminder:${reminder.id}:${scheduled.millisecondsSinceEpoch}',
    );
    if (reminder.type == 'medicine') {
      await _plugin.zonedSchedule(
        id: notificationId + 8,
        title: '${reminder.displayLabel}尚未确认',
        body: '如已服用请及时记录；如未服用，请遵循医嘱处理。',
        scheduledDate: scheduled.add(const Duration(minutes: 30)),
        notificationDetails: _buildDetails(reminder),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: matchDateTimeComponents,
        payload: 'reminder:${reminder.id}:${scheduled.millisecondsSinceEpoch}',
      );
    }
  }

  void _handleNotificationResponse(NotificationResponse response) {
    final payload = response.payload ?? '';
    if (payload.startsWith('medicine-group:')) {
      if (_notificationTapController.hasListener) {
        _notificationTapController.add(0);
      } else {
        _pendingNotificationReminderId = 0;
      }
      return;
    }
    if (!payload.startsWith('reminder:')) return;
    final parts = payload.split(':');
    final reminderId = parts.length >= 2 ? int.tryParse(parts[1]) : null;
    if (reminderId == null) return;
    final action = response.actionId;
    if (action == 'medicine_taken' ||
        action == 'medicine_skipped' ||
        action == 'medicine_snooze') {
      final event = MedicationNotificationAction(
        reminderId,
        switch (action) {
          'medicine_taken' => 'taken',
          'medicine_skipped' => 'skipped',
          _ => 'snooze',
        },
        parts.length >= 3
            ? DateTime.fromMillisecondsSinceEpoch(
                int.tryParse(parts[2]) ?? DateTime.now().millisecondsSinceEpoch,
              )
            : null,
      );
      if (_medicationActionController.hasListener) {
        _medicationActionController.add(event);
      } else {
        _pendingMedicationAction = event;
      }
      return;
    }
    if (_notificationTapController.hasListener) {
      _notificationTapController.add(reminderId);
    } else {
      _pendingNotificationReminderId = reminderId;
    }
  }

  NotificationDetails _buildDetails(
    ReminderData reminder, {
    bool includeMedicineActions = true,
  }) {
    const medicineActions = [
      AndroidNotificationAction(
        'medicine_taken',
        '已服',
        showsUserInterface: true,
      ),
      AndroidNotificationAction(
        'medicine_skipped',
        '跳过',
        showsUserInterface: true,
      ),
      AndroidNotificationAction(
        'medicine_snooze',
        '延后10分钟',
        showsUserInterface: true,
      ),
    ];
    final android = reminder.channel == 'local'
        ? AndroidNotificationDetails(
            _dailyChannelId,
            _dailyChannelName,
            channelDescription: _dailyChannelDesc,
            importance: Importance.high,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
            category: AndroidNotificationCategory.reminder,
            visibility: NotificationVisibility.private,
            actions: reminder.type == 'medicine' && includeMedicineActions
                ? medicineActions
                : null,
          )
        : AndroidNotificationDetails(
            _planChannelId,
            _planChannelName,
            channelDescription: _planChannelDesc,
            importance: Importance.high,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
            category: AndroidNotificationCategory.reminder,
            visibility: NotificationVisibility.private,
            actions: reminder.type == 'medicine' && includeMedicineActions
                ? medicineActions
                : null,
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

  String _medicineNotificationBody(
    ReminderData reminder, [
    TimeOfDayValue? time,
  ]) {
    final occurrenceTime = time ?? reminder.dailyTimes.first;
    final dose = reminder.doseAt(occurrenceTime);
    final instructions = reminder.instructionsAt(occurrenceTime);
    final details = [dose, instructions].where((item) => item.isNotEmpty);
    return details.isEmpty ? '请按医嘱用药并记录结果' : details.join(' · ');
  }

  Future<void> snoozeMedication(
    ReminderData reminder, {
    int minutes = 10,
  }) async {
    if (!_supported || reminder.id == null) return;
    final scheduled = tz.TZDateTime.now(tz.local).add(
      Duration(minutes: minutes),
    );
    await _plugin.zonedSchedule(
      id: reminder.id! * 1000 + 998,
      title: '${reminder.displayLabel}用药提醒',
      body: _medicineNotificationBody(reminder),
      scheduledDate: scheduled,
      notificationDetails: _buildDetails(reminder),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: 'reminder:${reminder.id}:${scheduled.millisecondsSinceEpoch}',
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

class _MedicationOccurrence {
  const _MedicationOccurrence({
    required this.reminder,
    required this.time,
    required this.scheduled,
  });

  final ReminderData reminder;
  final TimeOfDayValue time;
  final tz.TZDateTime scheduled;
}
