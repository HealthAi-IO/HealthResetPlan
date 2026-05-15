import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/app_theme.dart';
import '../../core/data/health_models.dart';
import '../../core/data/health_repository.dart';
import '../../core/crypto/key_vault.dart';
import '../../core/di/service_locator.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final HealthRepository _repo = sl<HealthRepository>();
  final KeyVault _vault = sl<KeyVault>();

  HealthDashboardData? _data;
  bool _loading = true;
  bool _syncReady = false;

  @override
  void initState() {
    super.initState();
    _repo.addListener(_onRepoChanged);
    _load();
    _loadSyncState();
  }

  @override
  void dispose() {
    _repo.removeListener(_onRepoChanged);
    super.dispose();
  }

  void _onRepoChanged() {
    _load(silent: true);
    _loadSyncState();
  }

  Future<void> _load({bool silent = false}) async {
    if (!mounted) return;
    if (!silent) {
      setState(() => _loading = true);
    }
    final data = await _repo.loadDashboard();
    if (!mounted) return;
    setState(() {
      _data = data;
      _loading = false;
    });
  }

  Future<void> _loadSyncState() async {
    final backedUp = await _vault.isBackedUp();
    if (!mounted) return;
    setState(() => _syncReady = backedUp);
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final profile = data?.profile;
    final bottomPadding =
        MediaQuery.sizeOf(context).width < 960 ? 100.0 : 20.0;
    if (_loading && data == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.fromLTRB(20, 20, 20, bottomPadding),
        children: [
          _HeroCard(
            profile: profile,
            syncReady: _syncReady,
            completion: data?.todayCompletion ?? 0,
          ),
          const SizedBox(height: 16),
          _SectionHeader(
            title: '快捷入口',
            actionLabel: '生成计划',
            onAction: () async {
              await _repo.generateWeeklyPlan();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已生成 7 天本地计划')),
              );
              context.go('/plan');
            },
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 900 ? 5 : 2;
              return GridView.count(
                crossAxisCount: columns,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: columns >= 4 ? 1.55 : 1.08,
                children: [
                  _ShortcutCard(
                    icon: Icons.assignment_ind,
                    title: '健康档案',
                    subtitle: '完善身高体重病史',
                    onTap: () => context.go('/profile'),
                  ),
                  _ShortcutCard(
                    icon: Icons.document_scanner_outlined,
                    title: '报告识别',
                    subtitle: '录入体检关键指标',
                    onTap: () => context.push('/report'),
                  ),
                  _ShortcutCard(
                    icon: Icons.event_note,
                    title: 'AI 计划',
                    subtitle: '生成饮食与运动方案',
                    onTap: () => context.go('/plan'),
                  ),
                  _ShortcutCard(
                    icon: Icons.check_circle,
                    title: '打卡记录',
                    subtitle: '饮食 / 运动 / 用药 / 称重',
                    onTap: () => context.go('/clock'),
                  ),
                  _ShortcutCard(
                    icon: Icons.lock_outline,
                    title: '云同步',
                    subtitle: _syncReady ? '已完成备份' : '尚未备份主密钥',
                    onTap: () => context.push('/sync/key-setup'),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          _SectionHeader(title: '今日概览'),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 900 ? 4 : 2;
              final latestBp = data?.latestIndicator('bp');
              final latestWeight = data?.latestIndicator('weight');
              return GridView.count(
                crossAxisCount: columns,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: columns >= 4 ? 1.65 : 1.55,
                children: [
                  _MetricCard(
                    title: 'BMI',
                    value:
                        profile == null ? '--' : profile.bmi.toStringAsFixed(1),
                    caption: profile?.bmiLevel ?? '待完善',
                    icon: Icons.monitor_weight_outlined,
                  ),
                  _MetricCard(
                    title: '最新血压',
                    value: latestBp?.displayValue ?? '未录入',
                    caption: latestBp == null
                        ? '可从报告或手动录入'
                        : _formatTime(latestBp.measuredTime),
                    icon: Icons.favorite_outline,
                  ),
                  _MetricCard(
                    title: '当前体重',
                    value: latestWeight?.displayValue ?? '--',
                    caption: latestWeight == null
                        ? '暂无体重记录'
                        : _formatTime(latestWeight.measuredTime),
                    icon: Icons.scale_outlined,
                  ),
                  _MetricCard(
                    title: '今日打卡',
                    value: '${data?.todayClockCount ?? 0}/4',
                    caption:
                        '完成率 ${((data?.todayCompletion ?? 0) * 100).round()}%',
                    icon: Icons.checklist_rtl_outlined,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 960;
              return wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: _Panel(
                            title: '体重趋势',
                            subtitle: '最近记录',
                            child: _WeightTrendChart(
                                values:
                                    data?.weightTrend(limit: 8) ?? const []),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 4,
                          child: _Panel(
                            title: '最近计划',
                            subtitle: '本地生成内容',
                            child:
                                _RecentPlanList(plans: data?.plans ?? const []),
                          ),
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        _Panel(
                          title: '体重趋势',
                          subtitle: '最近记录',
                          child: _WeightTrendChart(
                              values: data?.weightTrend(limit: 8) ?? const []),
                        ),
                        const SizedBox(height: 16),
                        _Panel(
                          title: '最近计划',
                          subtitle: '本地生成内容',
                          child:
                              _RecentPlanList(plans: data?.plans ?? const []),
                        ),
                      ],
                    );
            },
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 960;
              return wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _Panel(
                            title: '最近打卡',
                            subtitle: '饮食、运动、用药、称重',
                            child: _RecentClockList(
                                records: data?.clockRecords ?? const []),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _Panel(
                            title: '提醒',
                            subtitle: '本地提醒规则',
                            child: _ReminderList(
                                reminders: data?.reminders ?? const []),
                          ),
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        _Panel(
                          title: '最近打卡',
                          subtitle: '饮食、运动、用药、称重',
                          child: _RecentClockList(
                              records: data?.clockRecords ?? const []),
                        ),
                        const SizedBox(height: 16),
                        _Panel(
                          title: '提醒',
                          subtitle: '本地提醒规则',
                          child: _ReminderList(
                              reminders: data?.reminders ?? const []),
                        ),
                      ],
                    );
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.profile,
    required this.syncReady,
    required this.completion,
  });

  final UserProfileData? profile;
  final bool syncReady;
  final double completion;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final name = profile?.nickname ?? '';
    final hasName = name.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            primary.withValues(alpha: 0.12),
            Colors.white,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(hasName ? '欢迎，$name' : '欢迎回来',
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Text(
                      profile == null
                          ? '请先完善健康档案，系统会自动给出本地计划与提醒。'
                          : '根据当前档案和最近记录，系统正在持续优化您的日常健康节奏。',
                      style:
                          const TextStyle(color: AppTheme.muted, height: 1.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _StatusChip(
                    text: syncReady ? '已备份主密钥' : '未完成备份',
                    color: syncReady ? Colors.green : Colors.orange,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${(completion * 100).round()}% 今日完成',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, color: AppTheme.deepBlue),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 10,
              value: completion,
              backgroundColor: primary.withValues(alpha: 0.08),
              valueColor: AlwaysStoppedAnimation<Color>(primary),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            syncReady ? '云同步已可用，敏感字段会在客户端加密后再上传。' : '开通云同步前，请先完成主密钥备份。',
            style: const TextStyle(color: AppTheme.muted),
          ),
        ],
      ),
    );
  }
}

class _ShortcutCard extends StatelessWidget {
  const _ShortcutCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.cardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppTheme.primaryBlue.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppTheme.deepBlue),
            ),
            const SizedBox(height: 12),
            Text(title,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppTheme.muted, height: 1.3),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.caption,
    required this.icon,
  });

  final String title;
  final String value;
  final String caption;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppTheme.deepBlue),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(title,
                    style:
                        const TextStyle(color: AppTheme.muted, fontSize: 12)),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
        ),
        if (actionLabel != null && onAction != null)
          TextButton(
            onPressed: onAction,
            child: Text(actionLabel!),
          ),
      ],
    );
  }
}

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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(subtitle,
              style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style:
            TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _RecentPlanList extends StatelessWidget {
  const _RecentPlanList({required this.plans});

  final List<PlanRecordData> plans;

  @override
  Widget build(BuildContext context) {
    if (plans.isEmpty) {
      return const _EmptyState(
        icon: Icons.event_note_outlined,
        text: '暂无本地计划，点击“生成计划”即可创建 7 天饮食与运动方案。',
      );
    }

    return Column(
      children: [
        for (final plan in plans.take(6))
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.pageBg,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryBlue.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      plan.type == 'meal'
                          ? Icons.restaurant_outlined
                          : Icons.directions_run_outlined,
                      color: AppTheme.deepBlue,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${plan.label} · ${DateFormat('MM月dd日').format(plan.date)}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          plan.summary,
                          style: const TextStyle(
                              color: AppTheme.muted, height: 1.4),
                        ),
                      ],
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

class _RecentClockList extends StatelessWidget {
  const _RecentClockList({required this.records});

  final List<ClockRecordData> records;

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      return const _EmptyState(
        icon: Icons.check_circle_outline,
        text: '暂无打卡记录，完成一次饮食、运动或称重后会显示在这里。',
      );
    }

    return Column(
      children: [
        for (final record in records.take(6))
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    record.type == 'meal'
                        ? Icons.restaurant_outlined
                        : record.type == 'exercise'
                            ? Icons.directions_run_outlined
                            : record.type == 'medicine'
                                ? Icons.medication_outlined
                                : Icons.scale_outlined,
                    color: AppTheme.deepBlue,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${record.label} · ${DateFormat('MM月dd日 HH:mm').format(record.clockTime)}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        record.note.isEmpty ? '已完成' : record.note,
                        style: const TextStyle(color: AppTheme.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ReminderList extends StatelessWidget {
  const _ReminderList({required this.reminders});

  final List<ReminderData> reminders;

  @override
  Widget build(BuildContext context) {
    if (reminders.isEmpty) {
      return const _EmptyState(
        icon: Icons.notifications_none_outlined,
        text: '暂无提醒规则，可以在打卡页快速添加。',
      );
    }

    return Column(
      children: [
        for (final reminder in reminders.take(6))
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.pageBg,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryBlue.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.notifications_active_outlined,
                        color: AppTheme.deepBlue, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${reminder.label} · ${reminder.timeText}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          reminder.payload['note'] as String? ?? '本地提醒',
                          style: const TextStyle(color: AppTheme.muted),
                        ),
                      ],
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

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 18),
      decoration: BoxDecoration(
        color: AppTheme.pageBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(icon, size: 32, color: AppTheme.deepBlue),
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.muted, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _WeightTrendChart extends StatelessWidget {
  const _WeightTrendChart({required this.values});

  final List<double> values;

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) {
      return const _EmptyState(
        icon: Icons.show_chart_outlined,
        text: '体重趋势需要至少两条记录。继续记录体重后，这里会自动显示折线图。',
      );
    }

    return SizedBox(
      height: 180,
      child: CustomPaint(
        painter: _TrendPainter(values),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter(this.values);

  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    final padding = 20.0;
    final chartWidth = size.width - padding * 2;
    final chartHeight = size.height - padding * 2;
    if (chartWidth <= 0 || chartHeight <= 0) return;

    final minValue = values.reduce((a, b) => a < b ? a : b);
    final maxValue = values.reduce((a, b) => a > b ? a : b);
    final span = (maxValue - minValue).abs() < 0.2 ? 0.6 : maxValue - minValue;

    final gridPaint = Paint()
      ..color = AppTheme.cardBorder
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final linePaint = Paint()
      ..color = AppTheme.deepBlue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final dotPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final dotStrokePaint = Paint()
      ..color = AppTheme.deepBlue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    for (var i = 0; i < 3; i++) {
      final dy = padding + chartHeight * i / 2;
      canvas.drawLine(
        Offset(padding, dy),
        Offset(size.width - padding, dy),
        gridPaint,
      );
    }

    final points = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      final dx = padding +
          chartWidth * (values.length == 1 ? 0 : i / (values.length - 1));
      final normalized = (values[i] - minValue) / span;
      final dy = padding + chartHeight - normalized * chartHeight;
      points.add(Offset(dx, dy));
    }

    if (points.isNotEmpty) {
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, linePaint);

      for (final point in points) {
        canvas.drawCircle(point, 5.5, dotPaint);
        canvas.drawCircle(point, 5.5, dotStrokePaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) =>
      oldDelegate.values != values;
}

String _formatTime(DateTime time) {
  return DateFormat('MM月dd日 HH:mm').format(time);
}
