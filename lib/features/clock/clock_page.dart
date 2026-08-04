import 'dart:async';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../app/app_theme.dart';
import '../../core/data/health_models.dart';
import '../../core/data/health_repository.dart';
import '../../core/di/service_locator.dart';
import '../../core/notification/reminder_consent.dart';
import '../../core/notification/reminder_scheduler.dart';
import '../../core/network/file_api.dart';
import '../../core/network/telemetry_api.dart';
import '../../core/storage/report_image_storage.dart';

class ClockPage extends StatefulWidget {
  const ClockPage({super.key, this.initialReminderId});

  final int? initialReminderId;

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
    _dayRefreshTimer = Timer(
      tomorrow.difference(now) + const Duration(seconds: 1),
      () {
        _load(silent: true);
        _scheduleDayRefresh();
      },
    );
  }

  @override
  void didUpdateWidget(covariant ClockPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialReminderId != oldWidget.initialReminderId) {
      _openInitialReminderIfNeeded();
    }
  }

  void _onRepoChanged() => _load(silent: true);

  Future<void> _load({bool silent = false}) async {
    if (!mounted) return;
    if (!silent) setState(() => _loading = true);
    final records = await _repo.loadClockRecords(limit: 60);
    final reminders = await _repo.loadReminders();
    final plans = await _repo.loadPlans(limit: 40);
    if (!mounted) return;
    setState(() {
      _records = records;
      _reminders = reminders;
      _plans = plans.where((p) => p.type != 'risk').toList(growable: false);
      _loading = false;
    });
    _openInitialReminderIfNeeded();
    await _checkNotificationPermission();
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
    try {
      await _scheduler.syncReminder(reminder);
    } catch (error, stackTrace) {
      debugPrint('Reminder scheduling failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
    if (!mounted) return;
    _showSnack(
      result.syncAlarm ? '提醒规则已保存，请在系统闹钟界面确认创建' : '提醒规则已保存',
    );
    if (result.syncAlarm) {
      await _syncReminderToSystemAlarm(reminder);
    }
  }

  Future<void> _editReminder(ReminderData reminder) async {
    final result = await _showSmoothDialog<_ReminderDraft>(
      builder: (_) => _ReminderDialog(type: reminder.type, reminder: reminder),
    );
    if (result == null) return;

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
    try {
      await _scheduler.syncReminder(updated);
    } catch (_) {}
    if (!mounted) return;
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
    await _repo.deleteReminder(id);
    final imageObjectKey = reminder.payload['imageObjectKey']?.toString() ?? '';
    if (imageObjectKey.isNotEmpty) {
      try {
        await sl<FileApi>().delete(imageObjectKey);
      } catch (_) {}
    }
    try {
      await _scheduler.cancelReminder(id);
    } catch (_) {}
  }

  Future<void> _toggleReminder(ReminderData reminder) async {
    final updated =
        await _repo.setReminderEnabled(reminder, !reminder.isEnabled);
    try {
      await _scheduler.syncReminder(updated);
    } catch (_) {}
    if (mounted) {
      _showSnack(reminder.isEnabled ? '提醒已暂停' : '提醒已恢复');
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

    final todayTargets = _buildTodayTargets(now);
    final doneTypes = todayRecords
        .where((r) => r.status == 'done')
        .map((r) => r.type)
        .toSet();
    final todayDone =
        todayTargets.where((target) => doneTypes.contains(target.type)).length;
    final todayTotal = todayTargets.length;
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
                      onTap: () => _clockWithNote('meal'),
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
                child: _RecordList(
                  records: todayRecords.isEmpty
                      ? _records.take(8).toList()
                      : todayRecords,
                ),
              );
              final reminderPanel = _Panel(
                title: '我的提醒',
                subtitle: '${DateFormat('MM月dd日').format(now)} · 只显示今天',
                child: _ReminderList(
                  reminders: _reminders,
                  onDelete: _deleteReminder,
                  onEdit: _editReminder,
                  onToggle: _toggleReminder,
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
  const _RecordList({required this.records});
  final List<ClockRecordData> records;

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
        for (final r in records.take(20))
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
                  Text(
                    DateFormat('HH:mm').format(r.clockTime),
                    style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
      ],
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
    required this.onSyncAlarm,
    required this.onOpen,
  });
  final List<ReminderData> reminders;
  final Future<void> Function(ReminderData) onDelete;
  final Future<void> Function(ReminderData) onEdit;
  final Future<void> Function(ReminderData) onToggle;
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
    final reminders = widget.reminders.where((reminder) {
      if (!reminder.occursOn(now)) return false;
      final todayAt = DateTime(
        now.year,
        now.month,
        now.day,
        reminder.remindTime.hour,
        reminder.remindTime.minute,
      );
      return todayAt.isAfter(now);
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
            child: Text('今天暂无待提醒事项。', style: TextStyle(color: AppTheme.muted)),
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
                                  reminder.label,
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
                            '${_reminderScheduleText(reminder)} · ${_reminderSourceText(reminder)} · ${reminder.payload['note'] as String? ?? reminder.label}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: reminder.isEnabled
                                  ? AppTheme.muted
                                  : AppTheme.muted.withValues(alpha: 0.65),
                              fontSize: 12,
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
    required this.onSyncAlarm,
    required this.onDelete,
  });

  final bool enabled;
  final Future<void> Function()? onToggle;
  final Future<void> Function()? onEdit;
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
class _ReminderDialog extends StatefulWidget {
  const _ReminderDialog({required this.type, this.reminder});
  final String type;
  final ReminderData? reminder;

  @override
  State<_ReminderDialog> createState() => _ReminderDialogState();
}

class _ReminderDialogState extends State<_ReminderDialog> {
  final _noteCtrl = TextEditingController();
  final _imagePicker = ImagePicker();
  TimeOfDay _time = const TimeOfDay(hour: 7, minute: 0);
  late DateTime _date;
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
    }
    _syncAlarm = reminder?.payload['syncAlarm'] == true ||
        (reminder == null &&
            widget.type == 'medicine' &&
            defaultTargetPlatform == TargetPlatform.android);
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
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
                decoration: const InputDecoration(labelText: '备注（选填）'),
              ),
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
                        final at = DateTime(
                          _date.year,
                          _date.month,
                          _date.day,
                          _time.hour,
                          _time.minute,
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

  String? get _validationMessage {
    if (_scheduleMode == 'weekly' && _weekdays.isEmpty) {
      return '请至少选择一个提醒星期';
    }
    if (_scheduleMode == 'once') {
      final at = DateTime(
        _date.year,
        _date.month,
        _date.day,
        _time.hour,
        _time.minute,
      );
      if (!at.isAfter(DateTime.now())) return '单次提醒时间必须晚于当前时间';
    }
    return null;
  }

  void _save() {
    Navigator.pop(
      context,
      _ReminderDraft(
        time: TimeOfDayValue(hour: _time.hour, minute: _time.minute),
        date: _date,
        scheduleMode: _scheduleMode,
        weekdays: _weekdays.toList()..sort(),
        note: _noteCtrl.text.trim().isEmpty ? _title : _noteCtrl.text.trim(),
        syncAlarm: _scheduleMode == 'weekly' && _syncAlarm,
        image: _image,
        imageMimeType: _imageMimeType(_image),
        removeExistingImage: _removeExistingImage,
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
  final next = reminder.nextOccurrence(DateTime.now());
  if (!reminder.isWeekly) {
    final prefix = next == null ? '结束于' : '下次';
    return '$prefix ${_dateText(reminder.remindTime)} ${reminder.timeText}';
  }
  final nextText = next == null
      ? '暂无下一次提醒'
      : '下次 ${next.month}月${next.day}日 周${_weekdayShort(next.weekday)} ${reminder.timeText}';
  return '$nextText · ${_weekdaysText(reminder.weekdays)}重复';
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
      _ => Icons.check_circle_outline,
    };

Color _typeColor(String type) => switch (type) {
      'meal' => Colors.orange,
      'exercise' => Colors.green,
      'medicine' => Colors.redAccent,
      'weight' => AppTheme.deepBlue,
      'water' => Colors.lightBlue,
      _ => AppTheme.deepBlue,
    };

String _clockTitle(String type) => switch (type) {
      'meal' => '饮食打卡',
      'exercise' => '运动打卡',
      'water' => '饮水打卡',
      _ => '打卡',
    };

String _clockHint(String type) => switch (type) {
      'meal' => '例如"低盐便当"、"清蒸鱼 + 杂粮饭"',
      'exercise' => '例如"快走 30 分钟"、"瑜伽 20 分钟"',
      'water' => '例如"200ml 温水"，或直接空白保存',
      _ => '可填写备注',
    };
