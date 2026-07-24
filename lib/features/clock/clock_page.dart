import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../app/app_theme.dart';
import '../../core/data/health_models.dart';
import '../../core/data/health_repository.dart';
import '../../core/di/service_locator.dart';
import '../../core/notification/reminder_scheduler.dart';
import '../../core/network/telemetry_api.dart';

class ClockPage extends StatefulWidget {
  const ClockPage({super.key});

  @override
  State<ClockPage> createState() => _ClockPageState();
}

class _ClockPageState extends State<ClockPage> {
  final HealthRepository _repo = sl<HealthRepository>();
  final ReminderScheduler _scheduler = sl<ReminderScheduler>();

  bool _loading = true;
  List<ClockRecordData> _records = const [];
  List<ReminderData> _reminders = const [];
  List<PlanRecordData> _plans = const [];

  @override
  void initState() {
    super.initState();
    _repo.addListener(_onRepoChanged);
    _load();
  }

  @override
  void dispose() {
    _repo.removeListener(_onRepoChanged);
    super.dispose();
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
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
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
            FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))
          ],
          decoration: const InputDecoration(
            labelText: '当前体重',
            hintText: '例如 70.5',
            suffixText: 'kg',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
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
    await _repo.addIndicator(
      type: 'weight',
      payload: {'weightKg': result},
    );
    if (!mounted) return;
    _showSnack('称重 $result kg 已记录 ✓');
  }

  Future<void> _openSystemAlarm(int hour, int minute, String label) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    final intent = AndroidIntent(
      action: 'android.intent.action.SET_ALARM',
      arguments: <String, dynamic>{
        'android.intent.extra.alarm.HOUR': hour,
        'android.intent.extra.alarm.MINUTES': minute,
        'android.intent.extra.alarm.MESSAGE': label,
        'android.intent.extra.alarm.VIBRATE': true,
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
      );
      if (mounted) {
        _showSnack('已打开系统闹钟，请在系统界面确认创建');
      }
    } catch (_) {
      if (mounted) _showSnack('无法打开系统闹钟，请在手机时钟 App 中手动创建');
    }
  }

  Future<void> _addReminder(String type) async {
    final result = await _showSmoothDialog<_ReminderDraft>(
      builder: (_) => _ReminderDialog(type: type),
    );
    if (result == null) return;
    await _repo.addReminder(type: type, time: result.time, note: result.note);
    try {
      await _scheduler.initialize();
      await _scheduler.requestPermission();
      await _scheduler.syncAll();
    } catch (_) {}
    if (!mounted) return;
    _showSnack(result.syncAlarm ? '提醒规则已保存，请在系统闹钟界面确认创建' : '提醒规则已保存');
    if (result.syncAlarm) {
      await _syncReminderToSystemAlarm(
        ReminderData(
          type: type,
          remindAt: DateTime(
            DateTime.now().year,
            DateTime.now().month,
            DateTime.now().day,
            result.time.hour,
            result.time.minute,
          ).millisecondsSinceEpoch,
          payload: const {},
          channel: 'local',
          status: 'pending',
          createdAt: 0,
          updatedAt: 0,
        ),
      );
    }
  }

  Future<String?> _showNoteDialog(
      {required String title, required String hint}) async {
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
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
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
      final target = _ClockTarget(type: reminder.type);
      targets.putIfAbsent(target.type, () => target);
    }

    const order = ['meal', 'exercise', 'medicine', 'weight', 'water'];
    return targets.values.toList(growable: false)
      ..sort((a, b) {
        final ai = order.indexOf(a.type);
        final bi = order.indexOf(b.type);
        return (ai == -1 ? order.length : ai)
            .compareTo(bi == -1 ? order.length : bi);
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
            child: LayoutBuilder(builder: (context, constraints) {
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
                      onTap: () => _clockWithNote('meal')),
                  _ClockTile(
                      icon: Icons.directions_run_outlined,
                      label: '运动',
                      color: Colors.green,
                      onTap: () => _clockWithNote('exercise')),
                  _ClockTile(
                      icon: Icons.medication_outlined,
                      label: '用药',
                      color: Colors.redAccent,
                      onTap: _clockMedicine),
                  _ClockTile(
                      icon: Icons.scale_outlined,
                      label: '称重',
                      color: AppTheme.deepBlue,
                      onTap: _clockWeight),
                  _ClockTile(
                      icon: Icons.water_drop_outlined,
                      label: '饮水',
                      color: Colors.lightBlue,
                      onTap: () => _clockWithNote('water')),
                ],
              );
            }),
          ),
          const SizedBox(height: 14),

          // 新增提醒
          _Panel(
            title: '新增提醒',
            subtitle: '仅提醒今天和明天',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ReminderChip(
                    label: '称重提醒',
                    icon: Icons.scale_outlined,
                    onTap: () => _addReminder('weight')),
                _ReminderChip(
                    label: '饮食提醒',
                    icon: Icons.restaurant_outlined,
                    onTap: () => _addReminder('meal')),
                _ReminderChip(
                    label: '运动提醒',
                    icon: Icons.directions_run_outlined,
                    onTap: () => _addReminder('exercise')),
                _ReminderChip(
                    label: '用药提醒',
                    icon: Icons.medication_outlined,
                    onTap: () => _addReminder('medicine')),
                _ReminderChip(
                    label: '饮水提醒',
                    icon: Icons.water_drop_outlined,
                    onTap: () => _addReminder('water')),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 今日打卡 + 提醒规则
          LayoutBuilder(builder: (context, constraints) {
            final wide = constraints.maxWidth >= 960;
            final recentPanel = _Panel(
              title: '今日打卡记录',
              subtitle:
                  '${DateFormat('MM月dd日').format(now)} · 共 ${todayRecords.length} 条',
              child: _RecordList(
                  records: todayRecords.isEmpty
                      ? _records.take(8).toList()
                      : todayRecords),
            );
            final reminderPanel = _Panel(
              title: '提醒规则',
              subtitle: '本地保存的计划提醒',
              child: _ReminderList(
                reminders: _reminders,
                onDelete: (id) async {
                  await _repo.deleteReminder(id);
                  try {
                    await _scheduler.syncAll();
                  } catch (_) {}
                },
                onSyncAlarm: _syncReminderToSystemAlarm,
              ),
            );
            if (wide) {
              return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: recentPanel),
                    const SizedBox(width: 12),
                    Expanded(child: reminderPanel),
                  ]);
            }
            return Column(children: [
              recentPanel,
              const SizedBox(height: 14),
              reminderPanel
            ]);
          }),
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
      child: Row(children: [
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('今日打卡进度',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 6),
            Text('$done / $total 条完成',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: rate,
                minHeight: 8,
                backgroundColor: Colors.white24,
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
          ]),
        ),
        const SizedBox(width: 16),
        Text('$pct%',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 36,
                fontWeight: FontWeight.w900)),
      ]),
    );
  }
}

// ── 打卡按钮 ─────────────────────────────────────────────────
class _ClockTile extends StatelessWidget {
  const _ClockTile(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});
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
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 8),
          Text(label,
              style: TextStyle(
                  fontWeight: FontWeight.w700, color: color, fontSize: 13)),
        ]),
      ),
    );
  }
}

// ── 提醒快捷芯片 ──────────────────────────────────────────────
class _ReminderChip extends StatelessWidget {
  const _ReminderChip(
      {required this.label, required this.icon, required this.onTap});
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
          color: AppTheme.deepBlue, fontWeight: FontWeight.w700, fontSize: 13),
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
        child:
            Text('暂无打卡记录，点击上方按钮开始打卡。', style: TextStyle(color: AppTheme.muted)),
      );
    }
    return Column(children: [
      for (final r in records.take(20))
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.pageBg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _typeColor(r.type).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_typeIcon(r.type),
                    color: _typeColor(r.type), size: 19),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Text('${r.label}  ',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 14)),
                        if (r.status == 'skip')
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                                color: Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(6)),
                            child: const Text('跳过',
                                style: TextStyle(
                                    color: Colors.orange,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700)),
                          ),
                      ]),
                      const SizedBox(height: 3),
                      Text(
                        r.note.isNotEmpty
                            ? r.note
                            : DateFormat('MM月dd日 HH:mm').format(r.clockTime),
                        style: const TextStyle(
                            color: AppTheme.muted, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ]),
              ),
              Text(
                DateFormat('HH:mm').format(r.clockTime),
                style: const TextStyle(color: AppTheme.muted, fontSize: 12),
              ),
            ]),
          ),
        ),
    ]);
  }
}

// ── 提醒规则列表 ──────────────────────────────────────────────
class _ReminderList extends StatefulWidget {
  const _ReminderList(
      {required this.reminders,
      required this.onDelete,
      required this.onSyncAlarm});
  final List<ReminderData> reminders;
  final Future<void> Function(int) onDelete;
  final Future<void> Function(ReminderData) onSyncAlarm;

  @override
  State<_ReminderList> createState() => _ReminderListState();
}

class _ReminderListState extends State<_ReminderList> {
  static const _collapsedCount = 4;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final reminders = widget.reminders;
    if (reminders.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('暂无提醒规则。', style: TextStyle(color: AppTheme.muted)),
      );
    }
    final visible = _expanded
        ? reminders
        : reminders.take(_collapsedCount).toList(growable: false);
    return Column(children: [
      for (final r in visible)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
            decoration: BoxDecoration(
                color: AppTheme.pageBg,
                borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.notifications_active_outlined,
                    color: AppTheme.deepBlue, size: 19),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${r.label}  ${r.timeText}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 14)),
                      Text(r.payload['note'] as String? ?? '本地规则',
                          style: const TextStyle(
                              color: AppTheme.muted, fontSize: 12)),
                    ]),
              ),
              if (defaultTargetPlatform == TargetPlatform.android)
                IconButton(
                  icon: const Icon(Icons.alarm_add_outlined,
                      size: 18, color: AppTheme.deepBlue),
                  tooltip: '同步到手机闹钟',
                  onPressed: () => widget.onSyncAlarm(r),
                ),
              IconButton(
                icon: const Icon(Icons.close, size: 18, color: AppTheme.muted),
                onPressed: r.id == null ? null : () => widget.onDelete(r.id!),
              ),
            ]),
          ),
        ),
      if (reminders.length > _collapsedCount)
        TextButton.icon(
          onPressed: () => setState(() => _expanded = !_expanded),
          icon: Icon(
              _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down),
          label: Text(_expanded ? '收起提醒' : '展开全部 ${reminders.length} 条'),
        ),
    ]);
  }
}

// ── 面板容器 ──────────────────────────────────────────────────
class _Panel extends StatelessWidget {
  const _Panel(
      {required this.title, required this.subtitle, required this.child});
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
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 3),
        Text(subtitle,
            style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
        const SizedBox(height: 14),
        child,
      ]),
    );
  }
}

// ── 提醒弹窗 ──────────────────────────────────────────────────
class _ReminderDialog extends StatefulWidget {
  const _ReminderDialog({required this.type});
  final String type;

  @override
  State<_ReminderDialog> createState() => _ReminderDialogState();
}

class _ReminderDialogState extends State<_ReminderDialog> {
  final _noteCtrl = TextEditingController();
  TimeOfDay _time = const TimeOfDay(hour: 7, minute: 0);
  bool _syncAlarm = false;

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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('新增$_title'),
      content: SizedBox(
        width: 360,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _noteCtrl,
            decoration: const InputDecoration(labelText: '备注（选填）'),
          ),
          const SizedBox(height: 14),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('提醒时间'),
            subtitle: Text(_time.format(context)),
            trailing: TextButton(onPressed: _pickTime, child: const Text('选择')),
          ),
          if (defaultTargetPlatform == TargetPlatform.android) ...[
            const Divider(height: 1),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('同步到手机闹钟', style: TextStyle(fontSize: 14)),
              subtitle:
                  const Text('将该时间写入系统时钟App', style: TextStyle(fontSize: 12)),
              value: _syncAlarm,
              onChanged: (v) => setState(() => _syncAlarm = v),
            ),
          ],
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: () => Navigator.pop(
              context,
              _ReminderDraft(
                time: TimeOfDayValue(hour: _time.hour, minute: _time.minute),
                note: _noteCtrl.text.trim().isEmpty
                    ? _title
                    : _noteCtrl.text.trim(),
                syncAlarm: _syncAlarm,
              )),
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
}

class _ReminderDraft {
  const _ReminderDraft(
      {required this.time, required this.note, this.syncAlarm = false});
  final TimeOfDayValue time;
  final String note;
  final bool syncAlarm;
}

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
