import 'dart:async';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_settings_controller.dart';
import '../../app/app_theme.dart';
import '../../core/data/health_models.dart';
import '../../core/data/health_repository.dart';
import '../../core/di/service_locator.dart';
import '../../core/feedback/clock_feedback_service.dart';
import '../../core/notification/reminder_consent.dart';
import '../../core/notification/reminder_scheduler.dart';
import '../../core/network/file_api.dart';
import '../../core/network/telemetry_api.dart';
import '../../core/storage/report_image_storage.dart';
import '../../core/widgets/numeric_picker_field.dart';
import '../meals/meal_input_args.dart';

part 'clock_widgets.dart';

String weightChangeDescription(double current, double? previous) {
  if (previous == null) return '今天的体重记录已经保存';
  final difference = current - previous;
  if (difference.abs() < 0.05) return '与上次持平';
  return difference < 0
      ? '较上次下降 ${difference.abs().toStringAsFixed(1)} kg'
      : '较上次上升 ${difference.toStringAsFixed(1)} kg';
}

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

  Future<void> _clockWater() async {
    var amount = 200;
    final result = await _showQuickClockSheet<int>(
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => _QuickClockSheet(
          title: '饮水打卡',
          description: '选择本次饮水量',
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final value in const [100, 200, 300, 500, 750])
                  ChoiceChip(
                    label: Text('$value ml'),
                    selected: amount == value,
                    onSelected: (_) => setSheetState(() => amount = value),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.flag_outlined),
              title: const Text('每日饮水目标'),
              subtitle: Text(
                appSettingsController.waterGoalMl == null
                    ? '未设置，只统计实际饮水量'
                    : '${appSettingsController.waterGoalMl} ml',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await _showWaterGoalPicker();
                if (sheetContext.mounted) setSheetState(() {});
              },
            ),
            if (appSettingsController.seniorMode)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.record_voice_over_outlined),
                title: const Text('记录后语音播报'),
                subtitle: const Text('默认关闭，可随时关闭'),
                value: appSettingsController.seniorClockVoice,
                onChanged: (value) async {
                  await appSettingsController.setSeniorClockVoice(value);
                  if (sheetContext.mounted) setSheetState(() {});
                },
              ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => Navigator.pop(sheetContext, amount),
              icon: const Icon(Icons.water_drop_outlined),
              label: Text('记录 $amount ml'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    final previousRecords = _todayRecords('water');
    final previousTotal = _waterTotal(previousRecords);
    final recordId = await _repo.addClockRecord(
      type: 'water',
      status: 'done',
      note: '饮水 $result ml',
      value: result,
      unit: 'ml',
    );
    sl<TelemetryApi>().record('clock_recorded');
    if (!mounted) return;
    final total = previousTotal + result;
    final count = previousRecords.length + 1;
    final goal = appSettingsController.waterGoalMl;
    final detail = goal == null
        ? count == 1
            ? '今天的第一杯水，已经记下了'
            : '今天累计 $total ml · 共 $count 次'
        : '今天已喝 $total / $goal ml · 完成 ${(total / goal * 100).clamp(0, 999).round()}%';
    final reachedGoal = goal != null && previousTotal < goal && total >= goal;
    _showClockResult(
      title: reachedGoal ? '已记录 $result ml · 今日目标完成' : '已记录 $result ml',
      detail: detail,
      icon: Icons.water_drop_outlined,
      onUndo: () => _repo.deleteClockRecord(recordId),
    );
    unawaited(
      ClockFeedbackService.acknowledge(
        message: reachedGoal
            ? '已记录饮水$result毫升，今天的饮水目标完成了'
            : '已记录饮水$result毫升，今天累计$total毫升',
        speak: appSettingsController.seniorMode &&
            appSettingsController.seniorClockVoice,
      ),
    );
  }

  Future<void> _clockExercise() async {
    var exercise = '快走';
    var duration = 30;
    final result = await _showQuickClockSheet<({String name, int minutes})>(
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => _QuickClockSheet(
          title: '运动打卡',
          description: '选择运动类型和时长',
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final value in const ['快走', '慢跑', '骑行', '瑜伽', '健身操'])
                  ChoiceChip(
                    label: Text(value),
                    selected: exercise == value,
                    onSelected: (_) => setSheetState(() => exercise = value),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              '运动时长',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final value in const [10, 20, 30, 45, 60])
                  ChoiceChip(
                    label: Text('$value 分钟'),
                    selected: duration == value,
                    onSelected: (_) => setSheetState(() => duration = value),
                  ),
              ],
            ),
            if (appSettingsController.seniorMode) ...[
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.record_voice_over_outlined),
                title: const Text('记录后语音播报'),
                subtitle: const Text('默认关闭，可随时关闭'),
                value: appSettingsController.seniorClockVoice,
                onChanged: (value) async {
                  await appSettingsController.setSeniorClockVoice(value);
                  if (sheetContext.mounted) setSheetState(() {});
                },
              ),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => Navigator.pop(
                sheetContext,
                (name: exercise, minutes: duration),
              ),
              icon: const Icon(Icons.directions_run_outlined),
              label: Text('记录 $exercise $duration 分钟'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    final previousRecords = _todayRecords('exercise');
    final previousMinutes = _exerciseTotal(previousRecords);
    final recordId = await _repo.addClockRecord(
      type: 'exercise',
      status: 'done',
      note: '${result.name} ${result.minutes} 分钟',
      value: result.minutes,
      unit: 'minute',
      detail: result.name,
    );
    sl<TelemetryApi>().record('clock_recorded');
    if (!mounted) return;
    final total = previousMinutes + result.minutes;
    final count = previousRecords.length + 1;
    _showClockResult(
      title: '${result.name} ${result.minutes} 分钟，已经记下了',
      detail: '今天累计 $total 分钟 · 共 $count 次',
      icon: Icons.directions_run_outlined,
      onUndo: () => _repo.deleteClockRecord(recordId),
    );
    unawaited(
      ClockFeedbackService.acknowledge(
        message: '已记录${result.name}${result.minutes}分钟，今天累计$total分钟',
        speak: appSettingsController.seniorMode &&
            appSettingsController.seniorClockVoice,
      ),
    );
  }

  List<ClockRecordData> _todayRecords(String type) {
    final now = DateTime.now();
    return _records.where((record) {
      final time = record.clockTime;
      return record.type == type &&
          record.status == 'done' &&
          time.year == now.year &&
          time.month == now.month &&
          time.day == now.day;
    }).toList();
  }

  int _waterTotal(Iterable<ClockRecordData> records) => records.fold(
        0,
        (total, record) => total + (record.waterMilliliters ?? 0),
      );

  int _exerciseTotal(Iterable<ClockRecordData> records) => records.fold(
        0,
        (total, record) => total + (record.exerciseMinutes ?? 0),
      );

  Future<void> _showWaterGoalPicker() async {
    final current = appSettingsController.waterGoalMl ?? 0;
    final selected = await _showQuickClockSheet<int>(
      builder: (sheetContext) => _QuickClockSheet(
        title: '每日饮水目标',
        description: '根据个人情况选择，也可以不设置',
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final value in const [0, 1200, 1500, 1800, 2000, 2500])
                ChoiceChip(
                  label: Text(value == 0 ? '不设置' : '$value ml'),
                  selected: current == value,
                  onSelected: (_) => Navigator.pop(sheetContext, value),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '如医生对饮水量有专门要求，请以医嘱为准。',
            style: TextStyle(
                color: Theme.of(sheetContext).colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
    if (selected == null) return;
    await appSettingsController.setWaterGoalMl(selected == 0 ? null : selected);
    if (mounted) setState(() {});
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
    final before = await _repo.loadMealsBetween(
      DateTime(now.year, now.month, now.day),
      DateTime(now.year, now.month, now.day + 1),
    );
    if (!mounted) return;
    final saved = await context.push<bool>(
      '/meals/input',
      extra: MealInputArgs(mealType: mealType, eatenDate: now),
    );
    if (saved != true || !mounted) return;
    final after = await _repo.loadMealsBetween(
      DateTime(now.year, now.month, now.day),
      DateTime(now.year, now.month, now.day + 1),
    );
    final previousIds = before.map((meal) => meal.id).toSet();
    final meal =
        after.where((item) => !previousIds.contains(item.id)).firstOrNull;
    if (meal == null || !mounted) return;
    _showClockResult(
      title: '${meal.mealLabel}已经记下了',
      detail:
          '${meal.name} · ${meal.totalCalories.round()} kcal · 今天共 ${after.length} 餐',
      icon: Icons.restaurant_outlined,
      onUndo: () => _repo.deleteMealRecord(meal),
    );
    unawaited(
      ClockFeedbackService.acknowledge(
        message: '${meal.mealLabel}已经记下了',
        speak: appSettingsController.seniorMode &&
            appSettingsController.seniorClockVoice,
      ),
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
    final note = result == 'skip' ? '本次跳过用药' : '本次已服药';
    final recordId = await _repo.addClockRecord(
      type: 'medicine',
      status: result,
      note: note,
      detail: result == 'done' ? '已服药' : '已跳过',
    );
    if (!mounted) return;
    final doneCount = _todayRecords('medicine')
            .where((record) => record.status == 'done')
            .length +
        (result == 'done' ? 1 : 0);
    _showClockResult(
      title: result == 'done' ? '本次用药已确认' : '本次用药已记录为跳过',
      detail: result == 'done' ? '今天已服 $doneCount 次' : '记录可在今天全部记录中更正',
      icon: Icons.medication_outlined,
      onUndo: () => _repo.deleteClockRecord(recordId),
    );
  }

  // 称重打卡：直接录入体重值，联动写入 health_indicator
  Future<void> _clockWeight() async {
    final picked = await showNumericPicker(
      context: context,
      title: '称重打卡（kg）',
      min: HealthRanges.minWeightKg,
      max: HealthRanges.maxWeightKg,
      step: 0.1,
      decimals: 1,
      initialValue: 65,
    );
    final result = picked?.value;
    if (result == null) return;
    final previousWeight = (await _repo.loadIndicators(
      type: 'weight',
      limit: 1,
    ))
        .firstOrNull
        ?.numericTrendValue;
    final measuredAt = DateTime.now();
    final previousProfile = await _repo.loadProfile();
    final recordId = await _repo.addClockRecord(
      type: 'weight',
      status: 'done',
      note: '体重 ${result.toStringAsFixed(1)} kg',
      value: result,
      unit: 'kg',
      clockAt: measuredAt,
    );
    await _repo.addIndicator(
      type: 'weight',
      payload: {'weightKg': result},
      measuredAt: measuredAt,
    );
    if (!mounted) return;
    _showClockResult(
      title: '已记录 ${result.toStringAsFixed(1)} kg',
      detail: weightChangeDescription(result, previousWeight),
      icon: Icons.scale_outlined,
      onUndo: () async {
        await _repo.deleteClockRecord(recordId);
        await _repo.deleteWeightMeasurementAt(measuredAt);
        if (previousProfile != null) await _repo.saveProfile(previousProfile);
      },
    );
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
                  _clockWater();
                },
                icon: const Icon(Icons.water_drop_outlined),
                label: const Text('记录饮水'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _clockExercise();
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
                  style: TextStyle(color: AppTheme.muted),
                ),
                const SizedBox(height: 12),
                _TodayRecordTotals(
                  records: records,
                  waterGoalMl: appSettingsController.waterGoalMl,
                ),
                Expanded(
                  child: ListView(
                    children: [
                      _RecordList(
                        records: records,
                        onEdit: (record) {
                          Navigator.pop(sheetContext);
                          _editClockRecord(record);
                        },
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

  Future<void> _editClockRecord(ClockRecordData record) async {
    if (record.type == 'meal') {
      final time = record.clockTime;
      final meals = await _repo.loadMealsBetween(
        DateTime(time.year, time.month, time.day),
        DateTime(time.year, time.month, time.day + 1),
      );
      final meal =
          meals.where((item) => item.eatenAt == record.clockAt).firstOrNull;
      if (meal == null || !mounted) {
        if (mounted) _showSnack('未找到对应餐食，请删除后重新记录');
        return;
      }
      await context.push('/meals/input', extra: meal);
      return;
    }
    if (record.type == 'water') {
      var amount = record.waterMilliliters ?? 200;
      final result = await _showQuickClockSheet<int>(
        builder: (sheetContext) => StatefulBuilder(
          builder: (context, setSheetState) => _QuickClockSheet(
            title: '更正饮水记录',
            description: '选择这次实际饮水量',
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final value in const [100, 200, 300, 500, 750])
                    ChoiceChip(
                      label: Text('$value ml'),
                      selected: amount == value,
                      onSelected: (_) => setSheetState(() => amount = value),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.pop(sheetContext, amount),
                child: Text('保存为 $amount ml'),
              ),
            ],
          ),
        ),
      );
      if (result == null) return;
      await _repo.updateClockRecord(
        record,
        note: '饮水 $result ml',
        value: result,
        unit: 'ml',
      );
      if (mounted) _showSnack('饮水记录已更正');
      return;
    }
    if (record.type == 'exercise') {
      var name = record.exerciseName.isEmpty ? '快走' : record.exerciseName;
      var minutes = record.exerciseMinutes ?? 30;
      final result = await _showQuickClockSheet<({String name, int minutes})>(
        builder: (sheetContext) => StatefulBuilder(
          builder: (context, setSheetState) => _QuickClockSheet(
            title: '更正运动记录',
            description: '选择实际运动类型和时长',
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final value in const ['快走', '慢跑', '骑行', '瑜伽', '健身操'])
                    ChoiceChip(
                      label: Text(value),
                      selected: name == value,
                      onSelected: (_) => setSheetState(() => name = value),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final value in const [10, 20, 30, 45, 60])
                    ChoiceChip(
                      label: Text('$value 分钟'),
                      selected: minutes == value,
                      onSelected: (_) => setSheetState(() => minutes = value),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.pop(
                  sheetContext,
                  (name: name, minutes: minutes),
                ),
                child: Text('保存 $name $minutes 分钟'),
              ),
            ],
          ),
        ),
      );
      if (result == null) return;
      await _repo.updateClockRecord(
        record,
        note: '${result.name} ${result.minutes} 分钟',
        value: result.minutes,
        unit: 'minute',
        detail: result.name,
      );
      if (mounted) _showSnack('运动记录已更正');
      return;
    }
    if (record.type == 'weight') {
      final result = await showNumericPicker(
        context: context,
        title: '更正体重（kg）',
        min: HealthRanges.minWeightKg,
        max: HealthRanges.maxWeightKg,
        step: 0.1,
        decimals: 1,
        initialValue: record.weightKilograms ?? 65,
      );
      final value = result?.value;
      if (value == null) return;
      await _repo.updateClockRecord(
        record,
        note: '体重 ${value.toStringAsFixed(1)} kg',
        value: value,
        unit: 'kg',
      );
      await _repo.updateWeightMeasurementAt(record.clockTime, value);
      if (mounted) _showSnack('体重记录已更正');
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
                  style: TextStyle(fontSize: 16, color: AppTheme.muted),
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: reminders.isEmpty
                      ? Center(
                          child: Text(
                            todayOnly ? '今天没有提醒' : '还没有提醒规则',
                            style: TextStyle(
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
                              color: Theme.of(context).scaffoldBackgroundColor,
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

  Future<T?> _showQuickClockSheet<T>({required WidgetBuilder builder}) {
    return showModalBottomSheet<T>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Align(
        alignment: Alignment.bottomCenter,
        child: Material(
          color: Theme.of(sheetContext).colorScheme.surfaceContainerLow,
          clipBehavior: Clip.antiAlias,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SafeArea(
              top: false,
              child: builder(sheetContext),
            ),
          ),
        ),
      ),
    );
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
    );
  }

  void _showClockResult({
    required String title,
    required String detail,
    required IconData icon,
    required Future<void> Function() onUndo,
  }) {
    final senior = appSettingsController.seniorMode;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: senior ? 8 : 6),
        margin: EdgeInsets.fromLTRB(16, 0, 16, senior ? 20 : 12),
        padding: EdgeInsets.symmetric(
          horizontal: senior ? 18 : 16,
          vertical: senior ? 16 : 12,
        ),
        content: Semantics(
          liveRegion: true,
          child: Row(
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.inversePrimary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: senior ? 20 : 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(detail, style: TextStyle(fontSize: senior ? 17 : 14)),
                  ],
                ),
              ),
            ],
          ),
        ),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () async {
            await onUndo();
            if (mounted) _showSnack('刚才的记录已撤销');
          },
        ),
      ),
    );
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
        persist: false,
        content: Text(message),
        duration: const Duration(seconds: 5),
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
    final targets = <String, _ClockTarget>{
      for (final type in const [
        'meal',
        'exercise',
        'medicine',
        'weight',
        'water',
      ])
        type: _ClockTarget(type: type),
    };

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
        records: todayRecords,
        waterGoalMl: appSettingsController.waterGoalMl,
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
                  childAspectRatio: constraints.maxWidth >= 600 ? 1.6 : 0.95,
                  children: [
                    _ClockTile(
                      icon: Icons.restaurant_outlined,
                      label: '饮食',
                      color: AppTheme.meal(context),
                      onTap: _recordMeal,
                    ),
                    _ClockTile(
                      icon: Icons.directions_run_outlined,
                      label: '运动',
                      color: AppTheme.exercise(context),
                      onTap: _clockExercise,
                    ),
                    _ClockTile(
                      icon: Icons.medication_outlined,
                      label: '用药',
                      color: AppTheme.medicine(context),
                      onTap: _clockMedicine,
                    ),
                    _ClockTile(
                      icon: Icons.scale_outlined,
                      label: '称重',
                      color: AppTheme.weight(context),
                      onTap: _clockWeight,
                    ),
                    _ClockTile(
                      icon: Icons.water_drop_outlined,
                      label: '饮水',
                      color: AppTheme.water(context),
                      onTap: _clockWater,
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
                  waterGoalMl: appSettingsController.waterGoalMl,
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
