import 'dart:async';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_settings_controller.dart';
import '../../app/app_theme.dart';
import '../../core/data/health_models.dart';
import '../../core/data/health_repository.dart';
import '../../core/di/service_locator.dart';
import '../../core/notification/reminder_consent.dart';
import '../../core/notification/reminder_scheduler.dart';
import '../../core/network/file_api.dart';
import '../../core/network/telemetry_api.dart';
import '../../core/storage/report_image_storage.dart';
import '../meals/meal_input_args.dart';

class ClockPage extends StatefulWidget {
  const ClockPage({
    super.key,
    this.initialReminderId,
    this.openReminderSettings = false,
  });

  final int? initialReminderId;
  final bool openReminderSettings;

  @override
  State<ClockPage> createState() => _ClockPageState();
}

class _ClockPageState extends State<ClockPage> with WidgetsBindingObserver {
  final HealthRepository _repo = sl<HealthRepository>();
  final ReminderScheduler _scheduler = sl<ReminderScheduler>();

  bool _loading = true;
  List<ClockRecordData> _records = const [];
  List<ReminderData> _reminders = const [];
  List<PlanRecordData> _plans = const [];
  int? _openedReminderId;
  bool _openedReminderSettings = false;
  bool _notificationPermissionChecked = false;
  Timer? _dayRefreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _repo.addListener(_onRepoChanged);
    _scheduleDayRefresh();
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _dayRefreshTimer?.cancel();
    _repo.removeListener(_onRepoChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _notificationPermissionChecked = false;
    _scheduleDayRefresh();
    _load(silent: true);
  }

  void _scheduleDayRefresh() {
    _dayRefreshTimer?.cancel();
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    var refreshAt = tomorrow;
    for (final reminder in _reminders) {
      if (!reminder.occursOn(now)) continue;
      for (final time in reminder.dailyTimes) {
        final reminderEnd = DateTime(
          now.year,
          now.month,
          now.day,
          time.hour,
          time.minute,
        ).add(const Duration(seconds: 1));
        if (reminderEnd.isAfter(now) && reminderEnd.isBefore(refreshAt)) {
          refreshAt = reminderEnd;
        }
      }
    }
    _dayRefreshTimer = Timer(
      refreshAt.difference(now),
      () => _load(silent: true),
    );
  }

  @override
  void didUpdateWidget(covariant ClockPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialReminderId != oldWidget.initialReminderId) {
      _openInitialReminderIfNeeded();
    }
    if (!widget.openReminderSettings) _openedReminderSettings = false;
    if (widget.openReminderSettings != oldWidget.openReminderSettings) {
      _openReminderSettingsIfNeeded();
    }
  }

  void _onRepoChanged() => _load(silent: true);

  Future<void> _load({bool silent = false}) async {
    if (!mounted) return;
    if (!silent) setState(() => _loading = true);
    final records = await _repo.loadClockRecords(limit: 60);
    var reminders = await _repo.loadReminders();
    List<ReminderData> expired = const [];
    List<ReminderData> archived = const [];
    try {
      expired = await _repo.cleanupExpiredOnceReminders(DateTime.now());
      archived = await _repo.archiveCompletedMedicationCourses(DateTime.now());
    } catch (_) {}
    if (expired.isNotEmpty || archived.isNotEmpty) {
      for (final reminder in [...expired, ...archived]) {
        final id = reminder.id;
        if (id != null) {
          try {
            await _scheduler.cancelReminder(id);
          } catch (_) {}
        }
        final imageObjectKey =
            reminder.payload['imageObjectKey']?.toString() ?? '';
        if (imageObjectKey.isNotEmpty) {
          try {
            await sl<FileApi>().delete(imageObjectKey);
          } catch (_) {}
        }
      }
      reminders = await _repo.loadReminders();
    }
    final plans = await _repo.loadPlans(limit: 40);
    if (!mounted) return;
    setState(() {
      _records = records;
      _reminders = reminders;
      _plans = plans.where((p) => p.type != 'risk').toList(growable: false);
      _loading = false;
    });
    _scheduleDayRefresh();
    _openInitialReminderIfNeeded();
    _openReminderSettingsIfNeeded();
    await _checkNotificationPermission();
  }

  void _openReminderSettingsIfNeeded() {
    if (!widget.openReminderSettings || _openedReminderSettings || !mounted) {
      return;
    }
    _openedReminderSettings = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showLongTermReminderManager();
    });
  }

  void _openInitialReminderIfNeeded() {
    final reminderId = widget.initialReminderId;
    if (reminderId == null || reminderId == _openedReminderId || !mounted) {
      return;
    }
    final reminder =
        _reminders.where((item) => item.id == reminderId).firstOrNull;
    if (reminder == null) return;
    _openedReminderId = reminderId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showReminderDetails(reminder);
    });
  }

  // 饮食 / 运动 / 饮水打卡：带备注弹窗
  Future<void> _clockWithNote(String type) async {
    final note = await _showNoteDialog(
      title: _clockTitle(type),
      hint: _clockHint(type),
    );
    if (note == null) return;
    await _repo.addClockRecord(type: type, status: 'done', note: note);
    sl<TelemetryApi>().record('clock_recorded');
    if (!mounted) return;
    _showSnack('${_clockTitle(type)}已保存 ✓');
  }

  Future<void> _recordMeal() async {
    final now = DateTime.now();
    final mealType = now.hour < 10
        ? 'breakfast'
        : now.hour < 15
            ? 'lunch'
            : now.hour < 21
                ? 'dinner'
                : 'late_night';
    await context.push(
      '/meals/input',
      extra: MealInputArgs(mealType: mealType, eatenDate: now),
    );
  }

  // 用药打卡：done / skip 二选一
  Future<void> _clockMedicine() async {
    final result = await _showSmoothDialog<String>(
      builder: (ctx) => AlertDialog(
        title: const Text('用药打卡'),
        content: const Text('请选择本次用药状态：'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, 'skip'),
            child: const Text('跳过'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'done'),
            child: const Text('已服药'),
          ),
        ],
      ),
    );
    if (result == null) return;
    final note = result == 'skip' ? '本次跳过用药' : '';
    await _repo.addClockRecord(type: 'medicine', status: result, note: note);
    if (!mounted) return;
    _showSnack(result == 'done' ? '用药打卡已保存 ✓' : '已记录跳过');
  }

  // 称重打卡：直接录入体重值，联动写入 health_indicator
  Future<void> _clockWeight() async {
    final ctrl = TextEditingController();
    final result = await _showSmoothDialog<double>(
      builder: (ctx) => AlertDialog(
        title: const Text('称重打卡'),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
          ],
          decoration: const InputDecoration(
            labelText: '当前体重',
            hintText: '例如 70.5',
            suffixText: 'kg',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final v = double.tryParse(ctrl.text);
              if (v != null && v >= 20 && v <= 300) Navigator.pop(ctx, v);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (result == null) return;
    // 写入打卡记录
    await _repo.addClockRecord(
      type: 'weight',
      status: 'done',
      note: '体重 $result kg',
    );
    // 联动写入健康指标
    await _repo.addIndicator(type: 'weight', payload: {'weightKg': result});
    if (!mounted) return;
    _showSnack('称重 $result kg 已记录 ✓');
  }

  Future<void> _completeSeniorTask(_SeniorClockTask task) async {
    final reminder = task.reminder;
    if (reminder?.type == 'medicine') {
      final updated = await _repo.recordMedicationAction(
        reminder!,
        'taken',
        scheduledAt: task.scheduledAt,
      );
      await _scheduler.syncReminder(updated);
    } else if (reminder != null) {
      final updated = await _repo.acknowledgeReminder(
        reminder,
        task.scheduledAt,
      );
      await _scheduler.syncReminder(updated);
    } else {
      await _repo.addClockRecord(type: task.type, status: 'done');
    }
    if (mounted) _showSnack('${task.title}已完成');
  }

  Future<void> _changeSeniorTask(_SeniorClockTask task) async {
    final reminder = task.reminder;
    if (reminder?.type == 'medicine') {
      final action = await _showSmoothDialog<String>(
        builder: (ctx) => AlertDialog(
          title: Text(task.completed ? '更正本次用药记录' : '本次用药操作'),
          content: const Text('请选择本次实际用药情况。更正后库存数量也会同步调整。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('返回'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.pop(ctx, 'skipped'),
              child: const Text('跳过本次'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'taken'),
              child: const Text('确认已服'),
            ),
          ],
        ),
      );
      if (action == null) return;
      final confirmed = await _showSmoothDialog<bool>(
        builder: (ctx) => AlertDialog(
          title: const Text('确认更正吗？'),
          content: Text(
              action == 'taken' ? '本次记录将改为“已服药”。' : '本次记录将改为“已跳过”，之后的提醒不受影响。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('返回'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确认更正'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      final updated = await _repo.recordMedicationAction(
        reminder!,
        action,
        scheduledAt: task.scheduledAt,
      );
      await _scheduler.syncReminder(updated);
      return;
    }

    final record = task.record;
    if (record?.id == null) return;
    final confirmed = await _showSmoothDialog<bool>(
      builder: (ctx) => AlertDialog(
        title: const Text('撤销本次完成记录吗？'),
        content: const Text('撤销后，这项任务会重新显示为待完成。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('返回'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认撤销'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _repo.deleteClockRecord(record!.id!);
  }

  Future<void> _showSeniorSupplement() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '补充记录',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _recordMeal();
                },
                icon: const Icon(Icons.restaurant_outlined),
                label: const Text('记录饮食'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _clockWithNote('water');
                },
                icon: const Icon(Icons.water_drop_outlined),
                label: const Text('记录饮水'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _clockWithNote('exercise');
                },
                icon: const Icon(Icons.directions_walk_outlined),
                label: const Text('记录临时运动'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _clockMedicine();
                },
                icon: const Icon(Icons.medication_outlined),
                label: const Text('补记用药'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _clockWeight();
                },
                icon: const Icon(Icons.scale_outlined),
                label: const Text('记录体重'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showTodayRecords(List<ClockRecordData> records) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * 0.78,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '今天全部记录',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(
                  '${DateFormat('M月d日 EEEE', 'zh_CN').format(DateTime.now())} · ${records.length} 条',
                  style: const TextStyle(color: AppTheme.muted),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView(
                    children: [
                      _RecordList(
                        records: records,
                        onDelete: (record) {
                          Navigator.pop(sheetContext);
                          _confirmDeleteRecord(record);
                        },
                        onCorrectMedicine: () {
                          Navigator.pop(sheetContext);
                          _showTodayMedicineCorrection();
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDeleteRecord(ClockRecordData record) async {
    final confirmed = await _showSmoothDialog<bool>(
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除这条记录吗？'),
        content: Text(
            '${record.label} · ${DateFormat('HH:mm').format(record.clockTime)}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true && record.id != null) {
      await _repo.deleteClockRecord(record.id!);
      if (mounted) _showSnack('记录已删除');
    }
  }

  Future<void> _showTodayMedicineCorrection() async {
    final now = DateTime.now();
    final todayRecords = _records.where((record) {
      final time = record.clockTime;
      return time.year == now.year &&
          time.month == now.month &&
          time.day == now.day;
    }).toList();
    final tasks = _buildSeniorClockTasks(now, todayRecords)
        .where((task) => task.type == 'medicine' && task.completed)
        .toList();
    if (tasks.isEmpty) {
      _showSnack('没有可更正的定时用药记录');
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '更正用药记录',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),
              for (final task in tasks)
                _SeniorCompletedTask(
                  task: task,
                  onChange: () {
                    Navigator.pop(sheetContext);
                    _changeSeniorTask(task);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openSystemAlarm(
    int hour,
    int minute,
    String label, {
    List<int> weekdays = const [],
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    final intent = AndroidIntent(
      action: 'android.intent.action.SET_ALARM',
      arguments: <String, dynamic>{
        'android.intent.extra.alarm.HOUR': hour,
        'android.intent.extra.alarm.MINUTES': minute,
        'android.intent.extra.alarm.MESSAGE': label,
        'android.intent.extra.alarm.VIBRATE': true,
        if (weekdays.isNotEmpty)
          'android.intent.extra.alarm.DAYS':
              weekdays.map((weekday) => weekday % 7 + 1).toList(),
      },
    );
    await intent.launch();
  }

  Future<void> _syncReminderToSystemAlarm(ReminderData reminder) async {
    try {
      await _openSystemAlarm(
        reminder.remindTime.hour,
        reminder.remindTime.minute,
        reminder.label,
        weekdays: reminder.isWeekly ? reminder.weekdays : const [],
      );
      if (mounted) {
        _showSnack('已打开系统闹钟，请在系统界面确认创建');
      }
    } catch (_) {
      if (mounted) _showSnack('无法打开系统闹钟，请在手机时钟 App 中手动创建');
    }
  }

  Future<void> _addReminder(String type) async {
    final consent = await confirmReminderUse(context, _scheduler);
    if (!mounted || consent == ReminderConsentResult.declined) return;
    if (consent == ReminderConsentResult.notificationsDisabled) {
      _showNotificationPermissionNotice('请先开启通知权限，再使用提醒');
      return;
    }
    final result = await _showSmoothDialog<_ReminderDraft>(
      builder: (_) => _ReminderDialog(type: type),
    );
    if (result == null) return;
    if (type == 'medicine' && !await _scheduler.ensureExactAlarmPermission()) {
      if (mounted) {
        _showSnack('请允许“闹钟和提醒”权限后再保存用药提醒');
      }
      return;
    }
    var imageObjectKey = '';
    if (result.image != null) {
      try {
        imageObjectKey = await sl<FileApi>().uploadImage(
          result.image!,
          HealthRepository.newClientId(),
        );
      } catch (_) {
        if (mounted) _showSnack('药品图片上传失败，请检查网络后重试');
        return;
      }
    }
    ReminderData reminder;
    try {
      reminder = await _repo.addReminder(
        type: type,
        time: result.time,
        date: result.date,
        scheduleMode: result.scheduleMode,
        weekdays: result.weekdays,
        note: result.note,
        imageObjectKey: imageObjectKey,
        imageMimeType: result.imageMimeType,
        syncAlarm: result.syncAlarm,
        payloadExtras: result.payloadExtras,
      );
    } catch (_) {
      if (imageObjectKey.isNotEmpty) {
        try {
          await sl<FileApi>().delete(imageObjectKey);
        } catch (_) {}
      }
      if (mounted) _showSnack('提醒保存失败，请重试');
      return;
    }
    var scheduled = true;
    try {
      await _scheduler.syncReminder(reminder);
    } catch (error, stackTrace) {
      scheduled = false;
      debugPrint('Reminder scheduling failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
    if (!mounted) return;
    if (!scheduled) {
      _showSnack('规则已保存，但系统通知未创建，可在提醒操作中重新同步');
    } else {
      _showSnack(
        result.syncAlarm ? '提醒规则已保存，请在系统闹钟界面确认创建' : '提醒规则已保存',
      );
    }
    if (result.syncAlarm) {
      await _syncReminderToSystemAlarm(reminder);
    }
  }

  Future<void> _editReminder(ReminderData reminder) async {
    final result = await _showSmoothDialog<_ReminderDraft>(
      builder: (_) => _ReminderDialog(type: reminder.type, reminder: reminder),
    );
    if (result == null) return;
    if (reminder.type == 'medicine' &&
        !await _scheduler.ensureExactAlarmPermission()) {
      if (mounted) {
        _showSnack('请允许“闹钟和提醒”权限后再保存用药提醒');
      }
      return;
    }

    final oldImageObjectKey =
        reminder.payload['imageObjectKey']?.toString() ?? '';
    var imageObjectKey = result.removeExistingImage ? '' : oldImageObjectKey;
    var imageMimeType = result.removeExistingImage
        ? ''
        : reminder.payload['imageMimeType']?.toString() ?? '';
    var uploadedImageObjectKey = '';
    if (result.image != null) {
      try {
        uploadedImageObjectKey = await sl<FileApi>().uploadImage(
          result.image!,
          HealthRepository.newClientId(),
        );
        imageObjectKey = uploadedImageObjectKey;
        imageMimeType = result.imageMimeType;
      } catch (_) {
        if (mounted) _showSnack('药品图片上传失败，请检查网络后重试');
        return;
      }
    }

    ReminderData updated;
    try {
      updated = await _repo.updateReminder(
        reminder: reminder,
        time: result.time,
        date: result.date,
        scheduleMode: result.scheduleMode,
        weekdays: result.weekdays,
        note: result.note,
        imageObjectKey: imageObjectKey,
        imageMimeType: imageMimeType,
        syncAlarm: result.syncAlarm,
        payloadExtras: result.payloadExtras,
      );
    } catch (_) {
      if (uploadedImageObjectKey.isNotEmpty) {
        try {
          await sl<FileApi>().delete(uploadedImageObjectKey);
        } catch (_) {}
      }
      if (mounted) _showSnack('提醒修改失败，请重试');
      return;
    }

    if (oldImageObjectKey.isNotEmpty && oldImageObjectKey != imageObjectKey) {
      try {
        await sl<FileApi>().delete(oldImageObjectKey);
      } catch (_) {}
    }
    var scheduled = true;
    try {
      await _scheduler.syncReminder(updated);
    } catch (error, stackTrace) {
      scheduled = false;
      debugPrint('Reminder scheduling failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
    if (!mounted) return;
    if (!scheduled) {
      _showSnack('规则已保存，但系统通知未创建，可在提醒操作中重新同步');
      return;
    }
    bool? notificationsEnabled;
    try {
      notificationsEnabled = await _scheduler.notificationsEnabled();
    } catch (_) {}
    if (!mounted) return;
    if (notificationsEnabled == false) {
      _showNotificationPermissionNotice('提醒已更新，但通知权限尚未开启');
    } else {
      _showSnack(
        result.syncAlarm ? '提醒已更新，请在系统闹钟界面确认修改' : '提醒已更新',
      );
    }
    if (result.syncAlarm) {
      await _syncReminderToSystemAlarm(updated);
    }
  }

  Future<void> _deleteReminder(ReminderData reminder) async {
    final id = reminder.id;
    if (id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除提醒'),
        content: Text('确认删除“${reminder.displayLabel}”吗？已经产生的记录会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('返回'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _repo.deleteReminder(id);
    final imageObjectKey = reminder.payload['imageObjectKey']?.toString() ?? '';
    if (imageObjectKey.isNotEmpty) {
      try {
        await sl<FileApi>().delete(imageObjectKey);
      } catch (_) {}
    }
    try {
      await _scheduler.syncAll();
    } catch (_) {}
  }

  Future<void> _toggleReminder(ReminderData reminder) async {
    final updated =
        await _repo.setReminderEnabled(reminder, !reminder.isEnabled);
    var scheduled = true;
    try {
      await _scheduler.syncReminder(updated);
    } catch (_) {
      scheduled = false;
    }
    if (mounted) {
      _showSnack(
        scheduled
            ? (reminder.isEnabled ? '提醒已暂停' : '提醒已恢复')
            : '规则已保存，但系统通知未创建，可在提醒操作中重新同步',
      );
    }
  }

  Future<void> _resyncReminder(ReminderData reminder) async {
    if (reminder.type == 'medicine' &&
        !await _scheduler.ensureExactAlarmPermission()) {
      if (mounted) _showSnack('请先允许“闹钟和提醒”权限');
      return;
    }
    try {
      await _scheduler.syncReminder(reminder);
      if (mounted) _showSnack('系统通知已重新同步');
    } catch (_) {
      if (mounted) _showSnack('系统通知同步失败，请检查权限后重试');
    }
  }

  Future<void> _showReminderDetails(ReminderData reminder) async {
    final edit = await _showSmoothDialog<bool>(
      builder: (context) => _ReminderDetailsDialog(reminder: reminder),
    );
    if (edit == true && reminder.channel == 'local' && mounted) {
      await _editReminder(reminder);
    }
  }

  Future<void> _showTodayReminderManager() =>
      _showReminderManager(todayOnly: true);

  Future<void> _showLongTermReminderManager() =>
      _showReminderManager(todayOnly: false);

  Future<void> _showReminderManager({required bool todayOnly}) async {
    final now = DateTime.now();
    final reminders = (todayOnly
            ? _reminders.where(
                (reminder) => reminder.isEnabled && reminder.occursOn(now),
              )
            : _reminders)
        .toList()
      ..sort((a, b) {
        if (a.type != b.type) return a.type == 'medicine' ? -1 : 1;
        return (a.remindTime.hour * 60 + a.remindTime.minute)
            .compareTo(b.remindTime.hour * 60 + b.remindTime.minute);
      });
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * 0.78,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  todayOnly ? '今天的用药和提醒' : '提醒设置',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  todayOnly
                      ? '${DateFormat('M月d日 EEEE', 'zh_CN').format(now)} · 只显示今天'
                      : '在这里管理长期和重复提醒规则。',
                  style: const TextStyle(fontSize: 16, color: AppTheme.muted),
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: reminders.isEmpty
                      ? Center(
                          child: Text(
                            todayOnly ? '今天没有提醒' : '还没有提醒规则',
                            style: const TextStyle(
                              fontSize: 18,
                              color: AppTheme.muted,
                            ),
                          ),
                        )
                      : ListView.separated(
                          itemCount: reminders.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final reminder = reminders[index];
                            final times = reminder.dailyTimes
                                .map((time) =>
                                    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}')
                                .join('、');
                            final schedule = reminder.type == 'medicine'
                                ? '精确闹钟'
                                : '普通提醒（近似调度）';
                            final detail = reminder.type == 'medicine'
                                ? '$times · ${_medicineDoseSummary(reminder)}'
                                : times;
                            return Material(
                              color: AppTheme.pageBg,
                              borderRadius: BorderRadius.circular(16),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 5,
                                ),
                                leading: Icon(
                                  reminder.type == 'medicine'
                                      ? Icons.medication_outlined
                                      : Icons.notifications_active_outlined,
                                  color: AppTheme.primaryBlue,
                                ),
                                title: Text(
                                  reminder.displayLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                subtitle: Text(
                                  '$detail\n$schedule',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () {
                                  Navigator.pop(sheetContext);
                                  _showReminderDetails(reminder);
                                },
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _addReminder('medicine');
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('添加用药（精确闹钟）'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _showSeniorReminderTypePicker();
                  },
                  icon: const Icon(Icons.notifications_active_outlined),
                  label: const Text('添加普通提醒'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showSeniorReminderTypePicker() async {
    final type = await _showSmoothDialog<String>(
      builder: (dialogContext) => AlertDialog(
        title: const Text('添加普通提醒'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SeniorReminderTypeTile(
              icon: Icons.restaurant_outlined,
              label: '饮食提醒',
              onTap: () => Navigator.pop(dialogContext, 'meal'),
            ),
            _SeniorReminderTypeTile(
              icon: Icons.directions_run_outlined,
              label: '运动提醒',
              onTap: () => Navigator.pop(dialogContext, 'exercise'),
            ),
            _SeniorReminderTypeTile(
              icon: Icons.scale_outlined,
              label: '称重提醒',
              onTap: () => Navigator.pop(dialogContext, 'weight'),
            ),
            _SeniorReminderTypeTile(
              icon: Icons.water_drop_outlined,
              label: '饮水提醒',
              onTap: () => Navigator.pop(dialogContext, 'water'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
        ],
      ),
    );
    if (type != null && mounted) await _addReminder(type);
  }

  Future<String?> _showNoteDialog({
    required String title,
    required String hint,
  }) async {
    final ctrl = TextEditingController();
    final result = await _showSmoothDialog<String>(
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return result;
  }

  Future<T?> _showSmoothDialog<T>({required WidgetBuilder builder}) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black.withValues(alpha: 0.22),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (context, animation, secondaryAnimation) => builder(context),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.98, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _checkNotificationPermission() async {
    if (_notificationPermissionChecked ||
        defaultTargetPlatform != TargetPlatform.android ||
        _reminders.isEmpty) {
      return;
    }
    _notificationPermissionChecked = true;
    bool? enabled;
    try {
      await _scheduler.initialize();
      enabled = await _scheduler.notificationsEnabled();
      if (enabled == false && await _scheduler.hasUserConsent()) {
        final granted = await _scheduler.requestPermission();
        enabled = await _scheduler.notificationsEnabled();
        if (granted != false && enabled != false) {
          await _scheduler.syncAll();
        }
      }
    } catch (_) {}
    if (enabled == false && mounted) {
      _showNotificationPermissionNotice('通知权限未开启，APP 提醒不会显示');
    }
  }

  void _showNotificationPermissionNotice(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: '去设置',
          onPressed: _openNotificationSettings,
        ),
      ),
    );
  }

  Future<void> _openNotificationSettings() async {
    final packageName = (await PackageInfo.fromPlatform()).packageName;
    try {
      await AndroidIntent(
        action: 'android.settings.APP_NOTIFICATION_SETTINGS',
        arguments: {
          'android.provider.extra.APP_PACKAGE': packageName,
        },
      ).launch();
    } catch (_) {
      await AndroidIntent(
        action: 'android.settings.APPLICATION_DETAILS_SETTINGS',
        data: 'package:$packageName',
      ).launch();
    }
  }

  List<_SeniorClockTask> _buildSeniorClockTasks(
    DateTime now,
    List<ClockRecordData> todayRecords,
  ) {
    final tasks = <_SeniorClockTask>[];
    final reminderTypes = <String>{};
    ClockRecordData? recordFor(String type) {
      for (final record in todayRecords) {
        if (record.type == type && record.status == 'done') return record;
      }
      return null;
    }

    for (final reminder in _reminders) {
      if (!reminder.isEnabled || !reminder.occursOn(now)) continue;
      reminderTypes.add(reminder.type);
      for (final time in reminder.dailyTimes) {
        final occurrence = DateTime(
          now.year,
          now.month,
          now.day,
          time.hour,
          time.minute,
        );
        final action = reminder.type == 'medicine'
            ? reminder.actionAt(occurrence)
            : reminder.acknowledgedAt(occurrence)
                ? 'done'
                : null;
        final record = action == null ? null : recordFor(reminder.type);
        final dose = reminder.doseAt(time);
        final instructions = reminder.instructionsAt(time);
        tasks.add(_SeniorClockTask(
          type: reminder.type,
          title: reminder.displayLabel,
          detail: [dose, instructions]
              .where((value) => value.isNotEmpty)
              .join(' · '),
          scheduledAt: occurrence,
          completed: action != null,
          skipped: action == 'skipped',
          record: record,
          reminder: reminder,
        ));
      }
    }

    final today = DateTime(now.year, now.month, now.day);
    for (final plan in _plans) {
      final date = plan.date;
      if (DateTime(date.year, date.month, date.day) != today) continue;
      final target = _targetFromPlan(plan.type);
      if (target == null || reminderTypes.contains(target.type)) continue;
      final record = recordFor(target.type);
      final scheduledAt = DateTime(
        now.year,
        now.month,
        now.day,
        switch (target.type) {
          'weight' => 7,
          'meal' => 12,
          _ => 18,
        },
        target.type == 'exercise' ? 30 : 0,
      );
      tasks.add(_SeniorClockTask(
        type: target.type,
        title: switch (target.type) {
          'meal' => '今日饮食',
          'exercise' => '今日运动',
          'weight' => '健康测量',
          _ => plan.label,
        },
        detail: plan.summary,
        scheduledAt: scheduledAt,
        completed: record != null,
        record: record,
        plan: plan,
      ));
    }

    tasks.sort((a, b) {
      if (a.completed != b.completed) return a.completed ? 1 : -1;
      final aOverdue = a.scheduledAt.isBefore(now);
      final bOverdue = b.scheduledAt.isBefore(now);
      if (aOverdue != bOverdue) return aOverdue ? -1 : 1;
      if (aOverdue && a.type != b.type) {
        if (a.type == 'medicine') return -1;
        if (b.type == 'medicine') return 1;
      }
      return a.scheduledAt.compareTo(b.scheduledAt);
    });
    return tasks;
  }

  List<_ClockTarget> _buildTodayTargets(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final targets = <String, _ClockTarget>{};

    for (final plan in _plans) {
      final planDay = DateTime(plan.date.year, plan.date.month, plan.date.day);
      if (planDay != today) continue;
      final target = _targetFromPlan(plan.type);
      if (target != null) targets.putIfAbsent(target.type, () => target);
    }

    for (final reminder in _reminders) {
      if (!reminder.occursOn(now)) continue;
      final target = _ClockTarget(type: reminder.type);
      targets.putIfAbsent(target.type, () => target);
    }

    const order = ['meal', 'exercise', 'medicine', 'weight', 'water'];
    return targets.values.toList(growable: false)
      ..sort((a, b) {
        final ai = order.indexOf(a.type);
        final bi = order.indexOf(b.type);
        return (ai == -1 ? order.length : ai).compareTo(
          bi == -1 ? order.length : bi,
        );
      });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const _ClockLoadingView();

    final now = DateTime.now();
    final todayRecords = _records.where((r) {
      final t = r.clockTime;
      return t.year == now.year && t.month == now.month && t.day == now.day;
    }).toList();

    if (appSettingsController.seniorMode) {
      return _SeniorClockView(
        tasks: _buildSeniorClockTasks(now, todayRecords),
        onComplete: _completeSeniorTask,
        onChange: _changeSeniorTask,
        onSupplement: _showSeniorSupplement,
        onManageReminders: _showTodayReminderManager,
        onRefresh: () => _load(silent: true),
      );
    }

    final todayTargets = _buildTodayTargets(now);
    final doneTypes = todayRecords
        .where((r) => r.status == 'done')
        .map((r) => r.type)
        .toSet();
    final todayDone =
        todayTargets.where((target) => doneTypes.contains(target.type)).length;
    final todayTotal = todayTargets.length;
    final medicineTasks = _buildSeniorClockTasks(now, todayRecords)
        .where((task) => task.type == 'medicine' && task.reminder != null)
        .toList();
    final medicineScheduledCount = medicineTasks.length;
    final medicineTakenCount =
        medicineTasks.where((task) => task.completed && !task.skipped).length;
    final bottomPad = MediaQuery.sizeOf(context).width < 960 ? 100.0 : 20.0;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        key: const PageStorageKey('clock-scroll'),
        padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPad),
        cacheExtent: 900,
        children: [
          // 今日进度卡片
          _TodayProgressCard(done: todayDone, total: todayTotal),
          const SizedBox(height: 14),

          // 快速打卡
          _Panel(
            title: '快速打卡',
            subtitle: '点击记录当前行为',
            child: LayoutBuilder(
              builder: (context, constraints) {
                final cols = constraints.maxWidth >= 600 ? 5 : 3;
                return GridView.count(
                  crossAxisCount: cols,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.95,
                  children: [
                    _ClockTile(
                      icon: Icons.restaurant_outlined,
                      label: '饮食',
                      color: Colors.orange,
                      onTap: _recordMeal,
                    ),
                    _ClockTile(
                      icon: Icons.directions_run_outlined,
                      label: '运动',
                      color: Colors.green,
                      onTap: () => _clockWithNote('exercise'),
                    ),
                    _ClockTile(
                      icon: Icons.medication_outlined,
                      label: '用药',
                      color: Colors.redAccent,
                      onTap: _clockMedicine,
                    ),
                    _ClockTile(
                      icon: Icons.scale_outlined,
                      label: '称重',
                      color: AppTheme.deepBlue,
                      onTap: _clockWeight,
                    ),
                    _ClockTile(
                      icon: Icons.water_drop_outlined,
                      label: '饮水',
                      color: Colors.lightBlue,
                      onTap: () => _clockWithNote('water'),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 14),

          // 新增提醒
          _Panel(
            title: '新增提醒',
            subtitle: '每天在设定时间提醒',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ReminderChip(
                  label: '称重提醒',
                  icon: Icons.scale_outlined,
                  onTap: () => _addReminder('weight'),
                ),
                _ReminderChip(
                  label: '饮食提醒',
                  icon: Icons.restaurant_outlined,
                  onTap: () => _addReminder('meal'),
                ),
                _ReminderChip(
                  label: '运动提醒',
                  icon: Icons.directions_run_outlined,
                  onTap: () => _addReminder('exercise'),
                ),
                _ReminderChip(
                  label: '用药提醒',
                  icon: Icons.medication_outlined,
                  onTap: () => _addReminder('medicine'),
                ),
                _ReminderChip(
                  label: '饮水提醒',
                  icon: Icons.water_drop_outlined,
                  onTap: () => _addReminder('water'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 今日打卡 + 提醒规则
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 960;
              final recentPanel = _Panel(
                title: '今日打卡记录',
                subtitle:
                    '${DateFormat('MM月dd日').format(now)} · 共 ${todayRecords.length} 条',
                child: _TodayRecordSummary(
                  records: todayRecords,
                  medicineScheduledCount: medicineScheduledCount,
                  medicineTakenCount: medicineTakenCount,
                  onViewAll: () => _showTodayRecords(todayRecords),
                ),
              );
              final todayReminders = _reminders
                  .where((reminder) =>
                      reminder.isEnabled && reminder.occursOn(now))
                  .toList();
              final reminderPanel = _Panel(
                title: '今日提醒',
                subtitle: '${DateFormat('MM月dd日').format(now)} · 今日提醒',
                child: _ReminderList(
                  reminders: todayReminders,
                  onDelete: _deleteReminder,
                  onEdit: _editReminder,
                  onToggle: _toggleReminder,
                  onResync: _resyncReminder,
                  onSyncAlarm: _syncReminderToSystemAlarm,
                  onOpen: _showReminderDetails,
                ),
              );
              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: recentPanel),
                    const SizedBox(width: 12),
                    Expanded(child: reminderPanel),
                  ],
                );
              }
              return Column(
                children: [
                  recentPanel,
                  const SizedBox(height: 14),
                  reminderPanel,
                ],
              );
            },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class _ClockLoadingView extends StatelessWidget {
  const _ClockLoadingView();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        _ClockSkeletonBlock(height: 126),
        SizedBox(height: 14),
        _ClockSkeletonBlock(height: 182),
        SizedBox(height: 14),
        _ClockSkeletonBlock(height: 132),
      ],
    );
  }
}

class _SeniorClockTask {
  const _SeniorClockTask({
    required this.type,
    required this.title,
    required this.detail,
    required this.scheduledAt,
    required this.completed,
    this.skipped = false,
    this.record,
    this.reminder,
    this.plan,
  });

  final String type;
  final String title;
  final String detail;
  final DateTime scheduledAt;
  final bool completed;
  final bool skipped;
  final ClockRecordData? record;
  final ReminderData? reminder;
  final PlanRecordData? plan;

  DateTime? get completedAt => record?.clockTime;
}

class _SeniorReminderTypeTile extends StatelessWidget {
  const _SeniorReminderTypeTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: AppTheme.primaryBlue),
      title: Text(
        label,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

class _SeniorClockView extends StatelessWidget {
  const _SeniorClockView({
    required this.tasks,
    required this.onComplete,
    required this.onChange,
    required this.onSupplement,
    required this.onManageReminders,
    required this.onRefresh,
  });

  final List<_SeniorClockTask> tasks;
  final Future<void> Function(_SeniorClockTask) onComplete;
  final Future<void> Function(_SeniorClockTask) onChange;
  final Future<void> Function() onSupplement;
  final Future<void> Function() onManageReminders;
  final Future<void> Function() onRefresh;

  Future<void> _showCompletedTasks(
    BuildContext context,
    List<_SeniorClockTask> completed,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * 0.7,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '今天已完成',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                const Text(
                  '如记录有误，可在这里更正。',
                  style: TextStyle(fontSize: 16, color: AppTheme.muted),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView(
                    children: [
                      for (final task in completed)
                        _SeniorCompletedTask(
                          task: task,
                          onChange: () {
                            Navigator.pop(sheetContext);
                            onChange(task);
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pending = tasks.where((task) => !task.completed).toList();
    final completed = tasks.where((task) => task.completed).toList();
    final current = pending.firstOrNull;
    final currentTasks = current == null
        ? <_SeniorClockTask>[]
        : current.type == 'medicine'
            ? pending
                .where((task) =>
                    task.type == 'medicine' &&
                    task.scheduledAt == current.scheduledAt)
                .toList()
            : [current];
    final upcoming =
        pending.where((task) => !currentTasks.contains(task)).take(2).toList();
    final now = DateTime.now();
    final bottomPad = MediaQuery.sizeOf(context).width < 960 ? 100.0 : 20.0;

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        key: const PageStorageKey('senior-clock-scroll'),
        padding: EdgeInsets.fromLTRB(16, 18, 16, bottomPad),
        children: [
          const Text(
            '今天完成情况',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            DateFormat('yyyy年M月d日 EEEE', 'zh_CN').format(now),
            style: const TextStyle(fontSize: 17, color: AppTheme.muted),
          ),
          const SizedBox(height: 18),
          if (current == null)
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Row(
                children: [
                  Icon(Icons.task_alt, color: Colors.green, size: 36),
                  SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      '今天的计划都完成了',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            )
          else
            _SeniorCurrentTask(
              tasks: currentTasks,
              overdue: current.scheduledAt.isBefore(now),
              onComplete: onComplete,
              onChange: onChange,
            ),
          if (upcoming.isNotEmpty) ...[
            const SizedBox(height: 16),
            _SeniorTaskSection(
              title: '接下来',
              tasks: upcoming,
              onComplete: onComplete,
              onChange: onChange,
            ),
          ],
          if (completed.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.cardBorder),
              ),
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                title: Text(
                  '今天已完成 ${completed.length} 项',
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                subtitle: const Text('点此更正记录'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showCompletedTasks(context, completed),
              ),
            ),
          ],
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onSupplement,
            icon: const Icon(Icons.add_circle_outline),
            label: const Text('补充记录'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onManageReminders,
            icon: const Icon(Icons.medication_outlined),
            label: const Text('今天的用药和提醒'),
          ),
        ],
      ),
    );
  }
}

class _SeniorCurrentTask extends StatelessWidget {
  const _SeniorCurrentTask({
    required this.tasks,
    required this.overdue,
    required this.onComplete,
    required this.onChange,
  });

  final List<_SeniorClockTask> tasks;
  final bool overdue;
  final Future<void> Function(_SeniorClockTask) onComplete;
  final Future<void> Function(_SeniorClockTask) onChange;

  @override
  Widget build(BuildContext context) {
    final task = tasks.first;
    final medicine = task.type == 'medicine';
    final multipleMedicines = medicine && tasks.length > 1;
    final warning = overdue && medicine;
    final color = warning ? Colors.redAccent : AppTheme.primaryBlue;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(warning ? Icons.error_outline : Icons.schedule,
                  color: color),
              const SizedBox(width: 8),
              Text(
                warning ? '当前任务 · 已逾时' : '当前任务',
                style: TextStyle(
                  color: color,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            DateFormat('HH:mm').format(task.scheduledAt),
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(_typeIcon(task.type), size: 34, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  multipleMedicines ? '用药 · 共 ${tasks.length} 种药' : task.title,
                  style: const TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          if (!multipleMedicines && task.detail.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(task.detail,
                style: const TextStyle(fontSize: 17, color: AppTheme.muted)),
          ],
          const SizedBox(height: 18),
          if (multipleMedicines)
            for (final medicineTask in tasks)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      medicineTask.title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (medicineTask.detail.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          medicineTask.detail,
                          style: const TextStyle(
                            fontSize: 16,
                            color: AppTheme.muted,
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: color,
                            ),
                            onPressed: () => onComplete(medicineTask),
                            child: const Text('确认已服'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () => onChange(medicineTask),
                          child: const Text('跳过'),
                        ),
                      ],
                    ),
                  ],
                ),
              )
          else ...[
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: color,
                minimumSize: const Size.fromHeight(62),
              ),
              onPressed: () => onComplete(task),
              icon: const Icon(Icons.check_circle_outline),
              label: Text(medicine ? '确认已服' : '确认完成'),
            ),
            if (medicine) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => onChange(task),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('更正 / 跳过'),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _SeniorTaskSection extends StatelessWidget {
  const _SeniorTaskSection({
    required this.title,
    required this.tasks,
    required this.onComplete,
    required this.onChange,
  });

  final String title;
  final List<_SeniorClockTask> tasks;
  final Future<void> Function(_SeniorClockTask) onComplete;
  final Future<void> Function(_SeniorClockTask) onChange;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          for (final task in tasks)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 78,
                    child: Text(
                      DateFormat('HH:mm').format(task.scheduledAt),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Icon(_typeIcon(task.type), color: _typeColor(task.type)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(task.title,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                  ),
                  FilledButton(
                    onPressed: () => onComplete(task),
                    child: Text(task.type == 'medicine' ? '已服' : '完成'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SeniorCompletedTask extends StatelessWidget {
  const _SeniorCompletedTask({required this.task, required this.onChange});

  final _SeniorClockTask task;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final time = task.completedAt == null
        ? ''
        : ' · ${DateFormat('HH:mm').format(task.completedAt!)}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 10, 12),
      child: Row(
        children: [
          Icon(
            task.skipped ? Icons.remove_circle_outline : Icons.check_circle,
            color: task.skipped ? Colors.orange : Colors.green,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${task.title}${task.skipped ? ' · 已跳过' : time}',
              style: const TextStyle(fontSize: 17),
            ),
          ),
          TextButton(onPressed: onChange, child: const Text('更正')),
        ],
      ),
    );
  }
}

class _ClockTarget {
  const _ClockTarget({required this.type});

  final String type;
}

_ClockTarget? _targetFromPlan(String type) {
  return switch (type) {
    'meal' => const _ClockTarget(type: 'meal'),
    'exercise' => const _ClockTarget(type: 'exercise'),
    'measurement' => const _ClockTarget(type: 'weight'),
    _ => null,
  };
}

class _ClockSkeletonBlock extends StatelessWidget {
  const _ClockSkeletonBlock({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.cardBorder),
      ),
    );
  }
}

// ── 今日进度卡片 ─────────────────────────────────────────────
class _TodayProgressCard extends StatelessWidget {
  const _TodayProgressCard({required this.done, required this.total});
  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final rate = total == 0 ? 0.0 : (done / total).clamp(0.0, 1.0);
    final pct = (rate * 100).round();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppTheme.accentGradient(context),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '今日打卡进度',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 6),
                Text(
                  '$done / $total 条完成',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: rate,
                    minHeight: 8,
                    backgroundColor: Colors.white24,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Text(
            '$pct%',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

// ── 打卡按钮 ─────────────────────────────────────────────────
class _ClockTile extends StatelessWidget {
  const _ClockTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: color,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 提醒快捷芯片 ──────────────────────────────────────────────
class _ReminderChip extends StatelessWidget {
  const _ReminderChip({
    required this.label,
    required this.icon,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 16, color: AppTheme.deepBlue),
      label: Text(label),
      onPressed: onTap,
      backgroundColor: AppTheme.pageBg,
      side: const BorderSide(color: AppTheme.cardBorder),
      labelStyle: const TextStyle(
        color: AppTheme.deepBlue,
        fontWeight: FontWeight.w700,
        fontSize: 13,
      ),
    );
  }
}

// ── 打卡记录列表 ──────────────────────────────────────────────
class _RecordList extends StatelessWidget {
  const _RecordList({
    required this.records,
    required this.onDelete,
    required this.onCorrectMedicine,
  });
  final List<ClockRecordData> records;
  final ValueChanged<ClockRecordData> onDelete;
  final VoidCallback onCorrectMedicine;

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text(
          '暂无打卡记录，点击上方按钮开始打卡。',
          style: TextStyle(color: AppTheme.muted),
        ),
      );
    }
    return Column(
      children: [
        for (final r in records)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.pageBg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: _typeColor(r.type).withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _typeIcon(r.type),
                      color: _typeColor(r.type),
                      size: 19,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '${r.label}  ',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            if (r.status == 'skip')
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.orange.shade50,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  '跳过',
                                  style: TextStyle(
                                    color: Colors.orange,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          r.note.isNotEmpty
                              ? r.note
                              : DateFormat('MM月dd日 HH:mm').format(r.clockTime),
                          style: const TextStyle(
                            color: AppTheme.muted,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: '记录操作',
                    onSelected: (value) {
                      if (value == 'correct') {
                        onCorrectMedicine();
                      } else {
                        onDelete(r);
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: r.type == 'medicine' ? 'correct' : 'delete',
                        child: Text(r.type == 'medicine' ? '更正用药' : '删除记录'),
                      ),
                    ],
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 0, 8),
                      child: Text(
                        DateFormat('HH:mm').format(r.clockTime),
                        style: const TextStyle(
                          color: AppTheme.muted,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _TodayRecordSummary extends StatelessWidget {
  const _TodayRecordSummary({
    required this.records,
    required this.medicineScheduledCount,
    required this.medicineTakenCount,
    required this.onViewAll,
  });

  final List<ClockRecordData> records;
  final int medicineScheduledCount;
  final int medicineTakenCount;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text(
          '今天还没有打卡记录。',
          style: TextStyle(color: AppTheme.muted),
        ),
      );
    }
    const order = ['meal', 'exercise', 'medicine', 'weight', 'water'];
    final groups = <String, List<ClockRecordData>>{};
    for (final record in records) {
      groups.putIfAbsent(record.type, () => []).add(record);
    }
    final visibleTypes = order.where(groups.containsKey);

    return Column(
      children: [
        for (final type in visibleTypes)
          _TodayRecordSummaryRow(
            type: type,
            records: groups[type]!,
            medicineScheduledCount: medicineScheduledCount,
            medicineTakenCount: medicineTakenCount,
          ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: onViewAll,
            icon: const Icon(Icons.receipt_long_outlined),
            label: const Text('查看今天全部记录'),
          ),
        ),
      ],
    );
  }
}

class _TodayRecordSummaryRow extends StatelessWidget {
  const _TodayRecordSummaryRow({
    required this.type,
    required this.records,
    required this.medicineScheduledCount,
    required this.medicineTakenCount,
  });

  final String type;
  final List<ClockRecordData> records;
  final int medicineScheduledCount;
  final int medicineTakenCount;

  @override
  Widget build(BuildContext context) {
    final latest = records.first;
    final summary = switch (type) {
      'medicine' when medicineScheduledCount > 0 =>
        '已服 $medicineTakenCount/$medicineScheduledCount 次',
      'weight' when latest.note.isNotEmpty => latest.note,
      _ => '今天 ${records.length} 次',
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: _typeColor(type).withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(_typeIcon(type), color: _typeColor(type), size: 21),
      ),
      title: Text(
        latest.label,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(summary, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Text(
        DateFormat('HH:mm').format(latest.clockTime),
        style: const TextStyle(color: AppTheme.muted),
      ),
    );
  }
}

// ── 提醒规则列表 ──────────────────────────────────────────────
class _ReminderList extends StatefulWidget {
  const _ReminderList({
    required this.reminders,
    required this.onDelete,
    required this.onEdit,
    required this.onToggle,
    required this.onResync,
    required this.onSyncAlarm,
    required this.onOpen,
  });
  final List<ReminderData> reminders;
  final Future<void> Function(ReminderData) onDelete;
  final Future<void> Function(ReminderData) onEdit;
  final Future<void> Function(ReminderData) onToggle;
  final Future<void> Function(ReminderData) onResync;
  final Future<void> Function(ReminderData) onSyncAlarm;
  final Future<void> Function(ReminderData) onOpen;

  @override
  State<_ReminderList> createState() => _ReminderListState();
}

class _ReminderListState extends State<_ReminderList> {
  static const _collapsedCount = 4;
  bool _expanded = false;
  int? _expandedActionReminderId;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final reminders = widget.reminders.where((item) {
      return item.occursOn(now) &&
          item.dailyTimes.any(
            (time) => DateTime(
              now.year,
              now.month,
              now.day,
              time.hour,
              time.minute,
            ).isAfter(now),
          );
    }).toList()
      ..sort((a, b) {
        if (a.isEnabled != b.isEnabled) return a.isEnabled ? -1 : 1;
        final aMinutes = a.remindTime.hour * 60 + a.remindTime.minute;
        final bMinutes = b.remindTime.hour * 60 + b.remindTime.minute;
        return aMinutes.compareTo(bMinutes);
      });

    if (reminders.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('今天暂无提醒。', style: TextStyle(color: AppTheme.muted)),
          ),
          const _ReminderSafetyNotice(),
        ],
      );
    }
    final visible = _expanded
        ? reminders
        : reminders.take(_collapsedCount).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...visible.map(_buildReminder),
        if (reminders.length > _collapsedCount)
          Center(
            child: TextButton.icon(
              onPressed: () => setState(() => _expanded = !_expanded),
              icon: Icon(
                _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
              ),
              label: Text(_expanded ? '收起提醒' : '展开全部 ${reminders.length} 条'),
            ),
          ),
        const _ReminderSafetyNotice(),
      ],
    );
  }

  Widget _buildReminder(ReminderData reminder) {
    final now = DateTime.now();
    final timeText = reminder.dailyTimes
        .where(
          (time) => DateTime(
            now.year,
            now.month,
            now.day,
            time.hour,
            time.minute,
          ).isAfter(now),
        )
        .map((time) =>
            '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}')
        .join('、');
    final imageObjectKey = reminder.payload['imageObjectKey']?.toString() ?? '';
    final imageProvider = reportImageProvider(imageObjectKey);
    final showActions =
        reminder.id != null && _expandedActionReminderId == reminder.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppTheme.pageBg,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            InkWell(
              onTap: () => widget.onOpen(reminder),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryBlue.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: imageProvider == null
                          ? const Icon(
                              Icons.notifications_active_outlined,
                              color: AppTheme.deepBlue,
                              size: 19,
                            )
                          : Image(
                              image: imageProvider,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.medication_outlined,
                                color: AppTheme.deepBlue,
                                size: 19,
                              ),
                            ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  reminder.displayLabel,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              if (!reminder.isEnabled)
                                const Text(
                                  '已暂停',
                                  style: TextStyle(
                                    color: AppTheme.muted,
                                    fontSize: 11,
                                  ),
                                ),
                            ],
                          ),
                          Text(
                            '今天 $timeText · ${_reminderSourceText(reminder)} · ${reminder.type == 'medicine' ? _medicineDoseSummary(reminder) : reminder.payload['note'] as String? ?? reminder.label}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: reminder.isEnabled
                                  ? AppTheme.muted
                                  : AppTheme.muted.withValues(alpha: 0.65),
                              fontSize: 12,
                            ),
                          ),
                          if (reminder.refillNeeded)
                            Text(
                              '库存不足，请及时补充',
                              style: TextStyle(
                                color: Colors.orange.shade800,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: showActions ? '收起操作' : '更多操作',
                      onPressed: () => setState(() {
                        _expandedActionReminderId =
                            showActions ? null : reminder.id;
                      }),
                      icon: AnimatedRotation(
                        turns: showActions ? 0.25 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: const Icon(Icons.more_vert),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              child: showActions
                  ? _ReminderActionBar(
                      enabled: reminder.isEnabled,
                      onToggle: () async {
                        setState(() => _expandedActionReminderId = null);
                        await widget.onToggle(reminder);
                      },
                      onEdit: reminder.channel == 'local'
                          ? () async {
                              setState(() => _expandedActionReminderId = null);
                              await widget.onEdit(reminder);
                            }
                          : null,
                      onResync: () async {
                        setState(() => _expandedActionReminderId = null);
                        await widget.onResync(reminder);
                      },
                      onSyncAlarm:
                          defaultTargetPlatform == TargetPlatform.android &&
                                  reminder.type == 'medicine' &&
                                  reminder.isWeekly
                              ? () async {
                                  setState(
                                    () => _expandedActionReminderId = null,
                                  );
                                  await widget.onSyncAlarm(reminder);
                                }
                              : null,
                      onDelete: () async {
                        setState(() => _expandedActionReminderId = null);
                        await widget.onDelete(reminder);
                      },
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReminderActionBar extends StatelessWidget {
  const _ReminderActionBar({
    required this.enabled,
    required this.onToggle,
    required this.onEdit,
    required this.onResync,
    required this.onSyncAlarm,
    required this.onDelete,
  });

  final bool enabled;
  final Future<void> Function()? onToggle;
  final Future<void> Function()? onEdit;
  final Future<void> Function() onResync;
  final Future<void> Function()? onSyncAlarm;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.05),
        border: const Border(top: BorderSide(color: AppTheme.cardBorder)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Wrap(
          alignment: WrapAlignment.end,
          spacing: 4,
          runSpacing: 2,
          children: [
            if (onToggle != null)
              TextButton.icon(
                onPressed: onToggle,
                icon: Icon(
                  enabled ? Icons.pause_outlined : Icons.play_arrow_outlined,
                  size: 18,
                ),
                label: Text(enabled ? '暂停' : '恢复'),
              ),
            if (onEdit != null)
              TextButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('编辑'),
              ),
            TextButton.icon(
              onPressed: onResync,
              icon: const Icon(Icons.sync_outlined, size: 18),
              label: const Text('重新同步'),
            ),
            if (onSyncAlarm != null)
              TextButton.icon(
                onPressed: onSyncAlarm,
                icon: const Icon(Icons.alarm_add_outlined, size: 18),
                label: const Text('同步闹钟'),
              ),
            TextButton.icon(
              onPressed: onDelete,
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('删除'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReminderSafetyNotice extends StatelessWidget {
  const _ReminderSafetyNotice();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 16, color: AppTheme.muted),
          SizedBox(width: 6),
          Expanded(
            child: Text(
              'APP 提醒可能受系统限制产生延迟，不用于紧急或关键医疗用途。',
              style: TextStyle(color: AppTheme.muted, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 面板容器 ──────────────────────────────────────────────────
class _Panel extends StatelessWidget {
  const _Panel({
    required this.title,
    required this.subtitle,
    required this.child,
  });
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Colors.white, Color(0xFFFDFEFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.cardBorder),
        boxShadow: [
          BoxShadow(
            color: AppTheme.deepBlue.withValues(alpha: 0.05),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: const TextStyle(color: AppTheme.muted, fontSize: 12),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

// ── 提醒弹窗 ──────────────────────────────────────────────────
class _MedicineTimeDraft {
  const _MedicineTimeDraft({
    required this.time,
    required this.dose,
    required this.instructions,
  });

  final TimeOfDay time;
  final String dose;
  final String instructions;

  _MedicineTimeDraft copyWith({
    TimeOfDay? time,
    String? dose,
    String? instructions,
  }) {
    return _MedicineTimeDraft(
      time: time ?? this.time,
      dose: dose ?? this.dose,
      instructions: instructions ?? this.instructions,
    );
  }
}

class _ReminderDialog extends StatefulWidget {
  const _ReminderDialog({required this.type, this.reminder});
  final String type;
  final ReminderData? reminder;

  @override
  State<_ReminderDialog> createState() => _ReminderDialogState();
}

class _ReminderDialogState extends State<_ReminderDialog> {
  final _noteCtrl = TextEditingController();
  final _strengthCtrl = TextEditingController();
  final _inventoryCtrl = TextEditingController();
  final _refillThresholdCtrl = TextEditingController();
  final _imagePicker = ImagePicker();
  TimeOfDay _time = const TimeOfDay(hour: 7, minute: 0);
  List<_MedicineTimeDraft> _medicineTimes = const [
    _MedicineTimeDraft(
      time: TimeOfDay(hour: 7, minute: 0),
      dose: '1 片',
      instructions: '',
    ),
  ];
  late DateTime _date;
  DateTime? _courseEndDate;
  String _scheduleMode = 'weekly';
  Set<int> _weekdays = {1, 2, 3, 4, 5, 6, 7};
  XFile? _image;
  String? _imageError;
  bool _removeExistingImage = false;
  late bool _syncAlarm;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _date = DateTime(now.year, now.month, now.day);
    final reminder = widget.reminder;
    if (reminder != null) {
      _time = TimeOfDay.fromDateTime(reminder.remindTime);
      _date = reminder.startDate;
      _scheduleMode = reminder.isWeekly ? 'weekly' : 'once';
      _weekdays = reminder.weekdays.toSet();
      _noteCtrl.text = reminder.payload['note']?.toString() ?? '';
      _medicineTimes = reminder.dailyTimes
          .map((time) => _MedicineTimeDraft(
                time: TimeOfDay(hour: time.hour, minute: time.minute),
                dose: reminder.doseAt(time),
                instructions: reminder.instructionsAt(time),
              ))
          .toList();
      _strengthCtrl.text = reminder.payload['strength']?.toString() ?? '';
      _inventoryCtrl.text =
          reminder.inventoryRemaining?.toStringAsFixed(0) ?? '';
      _refillThresholdCtrl.text =
          reminder.refillThreshold?.toStringAsFixed(0) ?? '';
      _courseEndDate = reminder.courseEndDate;
    }
    _syncAlarm = reminder?.payload['syncAlarm'] == true ||
        (reminder == null &&
            widget.type == 'medicine' &&
            defaultTargetPlatform == TargetPlatform.android);
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    _strengthCtrl.dispose();
    _inventoryCtrl.dispose();
    _refillThresholdCtrl.dispose();
    super.dispose();
  }

  String get _title => switch (widget.type) {
        'meal' => '饮食提醒',
        'exercise' => '运动提醒',
        'medicine' => '用药提醒',
        'weight' => '称重提醒',
        'water' => '饮水提醒',
        _ => '提醒',
      };

  String get _existingImageObjectKey =>
      widget.reminder?.payload['imageObjectKey']?.toString() ?? '';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.reminder == null ? '新增$_title' : '编辑$_title'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _noteCtrl,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: widget.type == 'medicine' ? '药品名称' : '备注（选填）',
                ),
              ),
              if (widget.type == 'medicine') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _strengthCtrl,
                  decoration: const InputDecoration(
                    labelText: '药品规格（选填）',
                    hintText: '例如 10mg/片',
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('单次提醒'),
                      selected: _scheduleMode == 'once',
                      onSelected: (_) => setState(() {
                        _scheduleMode = 'once';
                        _syncAlarm = false;
                        final selectedTime = widget.type == 'medicine'
                            ? _medicineTimes.first.time
                            : _time;
                        final at = DateTime(
                          _date.year,
                          _date.month,
                          _date.day,
                          selectedTime.hour,
                          selectedTime.minute,
                        );
                        if (!at.isAfter(DateTime.now())) {
                          _date = _date.add(const Duration(days: 1));
                        }
                      }),
                    ),
                    ChoiceChip(
                      label: const Text('每周重复'),
                      selected: _scheduleMode == 'weekly',
                      onSelected: (_) =>
                          setState(() => _scheduleMode = 'weekly'),
                    ),
                  ],
                ),
              ),
              if (_scheduleMode == 'once')
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('提醒日期'),
                  subtitle: Text(_dateText(_date)),
                  trailing: TextButton(
                    onPressed: _pickDate,
                    child: const Text('选择'),
                  ),
                ),
              if (_scheduleMode == 'weekly') ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (var day = 1; day <= 7; day++)
                        ChoiceChip(
                          label: Text(_weekdayShort(day)),
                          selected: _weekdays.contains(day),
                          onSelected: (selected) => setState(() {
                            if (selected) {
                              _weekdays.add(day);
                            } else {
                              _weekdays.remove(day);
                            }
                          }),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 4,
                    children: [
                      TextButton(
                        onPressed: () => setState(
                          () => _weekdays = {1, 2, 3, 4, 5, 6, 7},
                        ),
                        child: const Text('每天'),
                      ),
                      TextButton(
                        onPressed: () =>
                            setState(() => _weekdays = {1, 2, 3, 4, 5}),
                        child: const Text('工作日'),
                      ),
                      TextButton(
                        onPressed: () => setState(() => _weekdays = {6, 7}),
                        child: const Text('周末'),
                      ),
                    ],
                  ),
                ),
              ],
              if (widget.type == 'medicine') ...[
                const SizedBox(height: 14),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '疗程结束日期（选填）',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _courseEndDate == null
                            ? '未设置'
                            : _dateText(_courseEndDate!),
                      ),
                    ),
                    if (_courseEndDate != null)
                      IconButton(
                        tooltip: '清除',
                        onPressed: () => setState(() => _courseEndDate = null),
                        icon: const Icon(Icons.clear),
                      ),
                    TextButton(
                      onPressed: _pickCourseEndDate,
                      child: const Text('选择'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _inventoryCtrl,
                  onChanged: (_) => setState(() {}),
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '剩余服用次数（选填）',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _refillThresholdCtrl,
                  onChanged: (_) => setState(() {}),
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '补药提醒阈值（选填）',
                  ),
                ),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (!kIsWeb &&
                          defaultTargetPlatform == TargetPlatform.android)
                        OutlinedButton.icon(
                          onPressed: () => _pickImage(ImageSource.camera),
                          icon: const Icon(Icons.camera_alt_outlined),
                          label: const Text('拍照'),
                        ),
                      OutlinedButton.icon(
                        onPressed: () => _pickImage(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library_outlined),
                        label: Text(
                          kIsWeb ||
                                  defaultTargetPlatform ==
                                      TargetPlatform.windows
                              ? '选择图片'
                              : '从相册选择',
                        ),
                      ),
                      if (_image != null ||
                          (_existingImageObjectKey.isNotEmpty &&
                              !_removeExistingImage))
                        TextButton(
                          onPressed: () => setState(() {
                            _image = null;
                            _removeExistingImage = true;
                            _imageError = null;
                          }),
                          child: const Text('移除'),
                        ),
                    ],
                  ),
                ),
                if (_image != null) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: FutureBuilder<Uint8List>(
                      future: _image!.readAsBytes(),
                      builder: (context, snapshot) {
                        final bytes = snapshot.data;
                        if (bytes == null) {
                          return const SizedBox(
                            height: 120,
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        return Image.memory(
                          bytes,
                          width: double.infinity,
                          height: 140,
                          fit: BoxFit.cover,
                        );
                      },
                    ),
                  ),
                ] else if (_existingImageObjectKey.isNotEmpty &&
                    !_removeExistingImage) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image(
                      image: reportImageProvider(_existingImageObjectKey)!,
                      width: double.infinity,
                      height: 140,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox(
                        height: 120,
                        child: Center(child: Text('药品图片加载失败')),
                      ),
                    ),
                  ),
                ],
                if (_imageError != null) ...[
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _imageError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 14),
              if (widget.type == 'medicine')
                Align(
                  alignment: Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '服药时间和剂量',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        '每个时间点可以设置不同剂量和用法',
                        style: TextStyle(color: AppTheme.muted, fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      for (var index = 0;
                          index < _medicineTimes.length;
                          index++)
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: AppTheme.pageBg,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListTile(
                            contentPadding:
                                const EdgeInsets.only(left: 12, right: 4),
                            title: Text(
                              _medicineTimes[index].time.format(context),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            subtitle: Text([
                              _medicineTimes[index].dose,
                              _medicineTimes[index].instructions,
                            ].where((value) => value.isNotEmpty).join(' · ')),
                            trailing: Wrap(
                              children: [
                                IconButton(
                                  tooltip: '编辑时间和剂量',
                                  onPressed: () => _editMedicineTime(index),
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                                if (_medicineTimes.length > 1)
                                  IconButton(
                                    tooltip: '删除这个时间',
                                    onPressed: () => setState(
                                      () => _medicineTimes.removeAt(index),
                                    ),
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      OutlinedButton.icon(
                        onPressed: _addMedicineTime,
                        icon: const Icon(Icons.add),
                        label: const Text('添加服药时间'),
                      ),
                    ],
                  ),
                )
              else
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('提醒时间'),
                  subtitle: Text(_time.format(context)),
                  trailing: TextButton(
                    onPressed: _pickTime,
                    child: const Text('选择'),
                  ),
                ),
              if (defaultTargetPlatform == TargetPlatform.android &&
                  widget.type == 'medicine' &&
                  _scheduleMode == 'weekly') ...[
                const Divider(height: 1),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('同步到手机闹钟', style: TextStyle(fontSize: 14)),
                  subtitle: const Text(
                    '将该时间写入系统时钟App',
                    style: TextStyle(fontSize: 12),
                  ),
                  value: _syncAlarm,
                  onChanged: (v) => setState(() => _syncAlarm = v),
                ),
              ],
              if (widget.type == 'medicine')
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 10),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    '建议同步到系统闹钟，确保准时提醒。APP 提醒不用于紧急或关键医疗用途。',
                    style: TextStyle(fontSize: 12, color: AppTheme.ink),
                  ),
                ),
              if (_validationMessage != null) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _validationMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _validationMessage == null ? _save : null,
          child: const Text('保存'),
        ),
      ],
    );
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked == null || !mounted) return;
    setState(() => _time = picked);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(DateTime.now().year + 10, 12, 31),
    );
    if (picked == null || !mounted) return;
    setState(() => _date = picked);
  }

  Future<void> _pickCourseEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _courseEndDate ?? _date,
      firstDate: _date,
      lastDate: DateTime(DateTime.now().year + 10, 12, 31),
    );
    if (picked != null && mounted) setState(() => _courseEndDate = picked);
  }

  Future<void> _addMedicineTime() async {
    if (_medicineTimes.length >= 6) return;
    final draft = await _showMedicineTimeEditor(
      _MedicineTimeDraft(
        time: _medicineTimes.last.time,
        dose: _medicineTimes.last.dose,
        instructions: _medicineTimes.last.instructions,
      ),
    );
    if (draft == null || !mounted) return;
    setState(() {
      _medicineTimes = [..._medicineTimes, draft]..sort((a, b) =>
          (a.time.hour * 60 + a.time.minute)
              .compareTo(b.time.hour * 60 + b.time.minute));
    });
  }

  Future<void> _editMedicineTime(int index) async {
    final draft = await _showMedicineTimeEditor(_medicineTimes[index]);
    if (draft == null || !mounted) return;
    setState(() {
      _medicineTimes[index] = draft;
      _medicineTimes.sort((a, b) => (a.time.hour * 60 + a.time.minute)
          .compareTo(b.time.hour * 60 + b.time.minute));
    });
  }

  Future<_MedicineTimeDraft?> _showMedicineTimeEditor(
    _MedicineTimeDraft initial,
  ) async {
    var selectedTime = initial.time;
    final doseController = TextEditingController(text: initial.dose);
    final instructionsController =
        TextEditingController(text: initial.instructions);
    try {
      return await showDialog<_MedicineTimeDraft>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('服药时间和剂量'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('服药时间'),
                  subtitle: Text(selectedTime.format(context)),
                  trailing: TextButton(
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: selectedTime,
                      );
                      if (picked != null) {
                        setDialogState(() => selectedTime = picked);
                      }
                    },
                    child: const Text('选择'),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: doseController,
                  decoration: const InputDecoration(
                    labelText: '本次剂量',
                    hintText: '例如 1 片',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: instructionsController,
                  decoration: const InputDecoration(
                    labelText: '本次用法（选填）',
                    hintText: '例如 饭后服用',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  final dose = doseController.text.trim();
                  if (dose.isEmpty) return;
                  Navigator.pop(
                    dialogContext,
                    initial.copyWith(
                      time: selectedTime,
                      dose: dose,
                      instructions: instructionsController.text.trim(),
                    ),
                  );
                },
                child: const Text('保存'),
              ),
            ],
          ),
        ),
      );
    } finally {
      doseController.dispose();
      instructionsController.dispose();
    }
  }

  String? get _validationMessage {
    if (widget.type == 'medicine') {
      if (_noteCtrl.text.trim().isEmpty) return '请输入药品名称';
      if (_medicineTimes.any((item) => item.dose.trim().isEmpty)) {
        return '请为每个服药时间填写剂量';
      }
      final timeKeys = _medicineTimes
          .map((item) => '${item.time.hour}:${item.time.minute}')
          .toSet();
      if (timeKeys.length != _medicineTimes.length) {
        return '服药时间不能重复';
      }
      if (_courseEndDate != null && _courseEndDate!.isBefore(_date)) {
        return '疗程结束日期不能早于开始日期';
      }
      final inventory = double.tryParse(_inventoryCtrl.text.trim());
      final threshold = double.tryParse(_refillThresholdCtrl.text.trim());
      if (_inventoryCtrl.text.trim().isNotEmpty &&
          (inventory == null || inventory < 0)) {
        return '剩余服用次数必须为非负数字';
      }
      if (_refillThresholdCtrl.text.trim().isNotEmpty &&
          (threshold == null || threshold < 0)) {
        return '补药提醒阈值必须为非负数字';
      }
      if (inventory != null && threshold != null && threshold > inventory) {
        return '补药提醒阈值不能大于当前剩余次数';
      }
    }
    if (_scheduleMode == 'weekly' && _weekdays.isEmpty) {
      return '请至少选择一个提醒星期';
    }
    if (_scheduleMode == 'once') {
      final primaryTime =
          widget.type == 'medicine' ? _medicineTimes.first.time : _time;
      final at = DateTime(
        _date.year,
        _date.month,
        _date.day,
        primaryTime.hour,
        primaryTime.minute,
      );
      if (!at.isAfter(DateTime.now())) return '单次提醒时间必须晚于当前时间';
    }
    return null;
  }

  void _save() {
    final primaryTime =
        widget.type == 'medicine' ? _medicineTimes.first.time : _time;
    final inventory = double.tryParse(_inventoryCtrl.text.trim());
    final threshold = double.tryParse(_refillThresholdCtrl.text.trim());
    Navigator.pop(
      context,
      _ReminderDraft(
        time: TimeOfDayValue(
          hour: primaryTime.hour,
          minute: primaryTime.minute,
        ),
        date: _date,
        scheduleMode: _scheduleMode,
        weekdays: _weekdays.toList()..sort(),
        note: _noteCtrl.text.trim().isEmpty ? _title : _noteCtrl.text.trim(),
        syncAlarm: _scheduleMode == 'weekly' && _syncAlarm,
        image: _image,
        imageMimeType: _imageMimeType(_image),
        removeExistingImage: _removeExistingImage,
        payloadExtras: widget.type == 'medicine'
            ? {
                'medicineName': _noteCtrl.text.trim(),
                'strength': _strengthCtrl.text.trim(),
                'dose': _medicineTimes.first.dose,
                'instructions': _medicineTimes.first.instructions,
                'dailyTimes': _medicineTimes
                    .map((item) => {
                          'hour': item.time.hour,
                          'minute': item.time.minute,
                        })
                    .toList(),
                'doseByTime': {
                  for (final item in _medicineTimes)
                    '${item.time.hour.toString().padLeft(2, '0')}:${item.time.minute.toString().padLeft(2, '0')}':
                        item.dose,
                },
                'instructionsByTime': {
                  for (final item in _medicineTimes)
                    if (item.instructions.isNotEmpty)
                      '${item.time.hour.toString().padLeft(2, '0')}:${item.time.minute.toString().padLeft(2, '0')}':
                          item.instructions,
                },
                if (_courseEndDate != null)
                  'courseEndAt': DateTime(
                    _courseEndDate!.year,
                    _courseEndDate!.month,
                    _courseEndDate!.day,
                  ).millisecondsSinceEpoch,
                if (inventory != null) 'inventoryRemaining': inventory,
                if (threshold != null) 'refillThreshold': threshold,
                'archived': false,
              }
            : const {},
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    final image = await _imagePicker.pickImage(
      source: source,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 82,
    );
    if (image == null) return;
    final extension = image.name.toLowerCase().split('.').last;
    if (!{'jpg', 'jpeg', 'png', 'webp'}.contains(extension)) {
      if (mounted) setState(() => _imageError = '仅支持 JPG、PNG 或 WebP 图片');
      return;
    }
    if (await image.length() > 5 * 1024 * 1024) {
      if (mounted) setState(() => _imageError = '图片不能超过 5MB');
      return;
    }
    if (mounted) {
      setState(() {
        _image = image;
        _removeExistingImage = false;
        _imageError = null;
      });
    }
  }
}

class _ReminderDraft {
  const _ReminderDraft({
    required this.time,
    required this.date,
    required this.scheduleMode,
    required this.weekdays,
    required this.note,
    this.syncAlarm = false,
    this.image,
    this.imageMimeType = '',
    this.removeExistingImage = false,
    this.payloadExtras = const {},
  });
  final TimeOfDayValue time;
  final DateTime date;
  final String scheduleMode;
  final List<int> weekdays;
  final String note;
  final bool syncAlarm;
  final XFile? image;
  final String imageMimeType;
  final bool removeExistingImage;
  final Map<String, Object?> payloadExtras;
}

class _ReminderDetailsDialog extends StatelessWidget {
  const _ReminderDetailsDialog({required this.reminder});

  final ReminderData reminder;

  @override
  Widget build(BuildContext context) {
    final note = reminder.payload['note']?.toString() ?? reminder.label;
    final imageObjectKey = reminder.payload['imageObjectKey']?.toString() ?? '';
    final imageProvider = reportImageProvider(imageObjectKey);
    return AlertDialog(
      title: Text(reminder.label),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (imageProvider != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image(
                    image: imageProvider,
                    width: double.infinity,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const SizedBox(
                      height: 180,
                      child: Center(child: Text('药品图片加载失败')),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              Text(
                _reminderScheduleText(reminder),
                style: const TextStyle(color: AppTheme.muted, fontSize: 13),
              ),
              const SizedBox(height: 10),
              Text(note),
              if (reminder.type == 'medicine') ...[
                const SizedBox(height: 10),
                if ((reminder.payload['strength']?.toString() ?? '').isNotEmpty)
                  Text('规格：${reminder.payload['strength']}'),
                const SizedBox(height: 6),
                for (final time in reminder.dailyTimes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Text(
                      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}  ${[
                        reminder.doseAt(time),
                        reminder.instructionsAt(time),
                      ].where((value) => value.isNotEmpty).join(' · ')}',
                    ),
                  ),
                if (reminder.inventoryRemaining != null)
                  Text(
                      '剩余库存：${reminder.inventoryRemaining!.toStringAsFixed(0)}'),
                if (reminder.courseEndDate != null)
                  Text(
                    '疗程结束：${DateFormat('yyyy-MM-dd').format(reminder.courseEndDate!)}',
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (reminder.channel == 'local')
          TextButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('编辑'),
          ),
        FilledButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('知道了'),
        ),
      ],
    );
  }
}

String _medicineDoseSummary(ReminderData reminder) {
  final values = reminder.dailyTimes
      .map((time) => reminder.doseAt(time))
      .where((value) => value.isNotEmpty)
      .toSet();
  if (values.isEmpty) return '按医嘱服用';
  return values.length == 1 ? values.first : '各时间剂量不同';
}

String _imageMimeType(XFile? image) {
  if (image == null) return '';
  final provided = image.mimeType;
  if (provided != null && provided.isNotEmpty) return provided;
  final extension = image.name.toLowerCase().split('.').last;
  return switch (extension) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'webp' => 'image/webp',
    _ => '',
  };
}

String _weekdayShort(int weekday) => switch (weekday) {
      1 => '一',
      2 => '二',
      3 => '三',
      4 => '四',
      5 => '五',
      6 => '六',
      7 => '日',
      _ => '',
    };

String _dateText(DateTime date) {
  return '${date.year}年${date.month}月${date.day}日 周${_weekdayShort(date.weekday)}';
}

String _weekdaysText(List<int> weekdays) {
  if (weekdays.length == 7) return '每天';
  if (weekdays.join(',') == '1,2,3,4,5') return '工作日';
  if (weekdays.join(',') == '6,7') return '周末';
  return weekdays.map((day) => '周${_weekdayShort(day)}').join('、');
}

String _reminderScheduleText(ReminderData reminder) {
  final times = reminder.dailyTimes
      .map((time) =>
          '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}')
      .join('、');
  if (!reminder.isWeekly) {
    return '${_dateText(reminder.remindTime)} $times';
  }
  return '${_weekdaysText(reminder.weekdays)} $times';
}

String _reminderSourceText(ReminderData reminder) => switch (reminder.source) {
      'manual' => '手动创建',
      'ai-plan' => 'AI 计划',
      'risk' => '风险建议',
      _ => '计划提醒',
    };

// ── 工具函数 ──────────────────────────────────────────────────
IconData _typeIcon(String type) => switch (type) {
      'meal' => Icons.restaurant_outlined,
      'exercise' => Icons.directions_run_outlined,
      'medicine' => Icons.medication_outlined,
      'weight' => Icons.scale_outlined,
      'water' => Icons.water_drop_outlined,
      'quit_smoking' => Icons.smoke_free_outlined,
      _ => Icons.check_circle_outline,
    };

Color _typeColor(String type) => switch (type) {
      'meal' => Colors.orange,
      'exercise' => Colors.green,
      'medicine' => Colors.redAccent,
      'weight' => AppTheme.deepBlue,
      'water' => Colors.lightBlue,
      'quit_smoking' => Colors.teal,
      _ => AppTheme.deepBlue,
    };

String _clockTitle(String type) => switch (type) {
      'meal' => '饮食打卡',
      'exercise' => '运动打卡',
      'water' => '饮水打卡',
      'quit_smoking' => '戒烟提醒',
      _ => '打卡',
    };

String _clockHint(String type) => switch (type) {
      'meal' => '例如"低盐便当"、"清蒸鱼 + 杂粮饭"',
      'exercise' => '例如"快走 30 分钟"、"瑜伽 20 分钟"',
      'water' => '例如"200ml 温水"，或直接空白保存',
      _ => '可填写备注',
    };
