import 'dart:math';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/app_theme.dart';
import '../../core/auth/user_session.dart';
import '../../core/data/health_models.dart';
import '../../core/data/health_repository.dart';
import '../../core/di/service_locator.dart';
import '../../core/membership/membership_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final HealthRepository _repo = sl<HealthRepository>();
  final MembershipService _membership = sl<MembershipService>();

  HealthDashboardData? _data;
  List<HealthIndicatorEntry> _recentIndicators = const [];
  MembershipStatus _memberStatus = MembershipStatus.free;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _repo.addListener(_onChanged);
    _load();
  }

  @override
  void dispose() {
    _repo.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => _load(silent: true);

  Future<void> _load({bool silent = false}) async {
    if (!mounted) return;
    if (!silent) setState(() => _loading = true);
    final cutoff = DateTime.now().subtract(const Duration(days: 3));
    final results = await Future.wait([
      _repo.loadDashboard(),
      _repo.loadIndicatorsSince(cutoff),
      _membership.getStatus(),
    ]);
    if (!mounted) return;
    setState(() {
      _data = results[0] as HealthDashboardData;
      _recentIndicators = results[1] as List<HealthIndicatorEntry>;
      _memberStatus = results[2] as MembershipStatus;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _data == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final data = _data;
    final profile = data?.profile;
    final bottomPad = MediaQuery.sizeOf(context).width < 960 ? 100.0 : 20.0;
    final now = DateTime.now();
    final todayLabel = DateFormat('MM月dd日 EEEE', 'zh_CN').format(now);
    final needsSetup = profile == null ||
        !profile.isComplete ||
        ((data?.indicators.isEmpty ?? true) && (data?.plans.isEmpty ?? true));

    // 今日计划
    final todayPlans = (data?.plans ?? []).where((p) {
      final d = p.date;
      return d.year == now.year && d.month == now.month && d.day == now.day;
    }).toList();
    final todayMeal = todayPlans.where((p) => p.type == 'meal').firstOrNull;
    final todayExercise =
        todayPlans.where((p) => p.type == 'exercise').firstOrNull;

    // 今日打卡
    final todayClocks = (data?.clockRecords ?? []).where((r) {
      final t = r.clockTime;
      return t.year == now.year && t.month == now.month && t.day == now.day;
    }).toList();
    final doneTypes =
        todayClocks.where((r) => r.status == 'done').map((r) => r.type).toSet();
    final completion = data?.todayCompletion ?? 0;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPad),
        children: [
          // 顶部仪表盘 Hero
          _DashboardHero(
            profile: profile,
            completion: completion,
            doneTypes: doneTypes,
            todayLabel: todayLabel,
            onClockTap: () => context.go('/clock'),
          ),
          const SizedBox(height: 14),

          if (needsSetup) ...[
            _SetupGuideCard(
              onProfile: () => context.go('/profile'),
              onIndicator: () => context.push('/indicators/input').then((_) {
                if (mounted) _load(silent: true);
              }),
              onDemo: () async {
                final messenger = ScaffoldMessenger.of(context);
                await _repo.resetDemoData();
                if (!mounted) return;
                messenger.showSnackBar(
                  const SnackBar(content: Text('已恢复本地示例数据')),
                );
              },
            ),
            const SizedBox(height: 14),
          ],

          // 今日关键指标
          _TodayMetricsRow(
              data: data,
              onAddIndicator: () {
                context.push('/indicators/input').then((_) {
                  if (mounted) _load(silent: true);
                });
              }),
          const SizedBox(height: 14),

          // 会员横幅（免费用户显示升级入口，会员显示状态）
          _HomeMembershipBanner(
            status: _memberStatus,
            onTap: () {
              if (!UserSession.instance.isAccountLogin) {
                context.push('/login', extra: true);
              } else {
                context.push('/membership').then((_) {
                  if (mounted) _load(silent: true);
                });
              }
            },
          ),
          const SizedBox(height: 14),

          // 今日计划摘要
          _TodayPlanCard(
            meal: todayMeal,
            exercise: todayExercise,
            onGenerate: () async {
              try {
                await _repo.generateWeeklyPlan();
                if (!mounted) return;
                ScaffoldMessenger.of(
                        context) // ignore: use_build_context_synchronously
                    .showSnackBar(const SnackBar(content: Text('已生成 7 天本地计划')));
              } catch (_) {
                if (!mounted) return;
                ScaffoldMessenger.of(
                        context) // ignore: use_build_context_synchronously
                    .showSnackBar(const SnackBar(content: Text('计划生成失败，请重试')));
              }
            },
            onViewAll: () => context.go('/plan'),
          ),
          const SizedBox(height: 14),

          // 快捷入口
          _Panel(
            title: '快捷入口',
            child: LayoutBuilder(builder: (_, c) {
              final cols = c.maxWidth >= 600 ? 6 : 3;
              return GridView.count(
                crossAxisCount: cols,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.95,
                children: [
                  _QuickEntry(
                      icon: Icons.assignment_ind_outlined,
                      label: '健康档案',
                      color: Colors.teal,
                      onTap: () => context.go('/profile')),
                  _QuickEntry(
                      icon: Icons.scale_outlined,
                      label: '录入指标',
                      color: AppTheme.deepBlue,
                      onTap: () {
                        context.push('/indicators/input').then((_) {
                          if (mounted) _load(silent: true);
                        });
                      }),
                  _QuickEntry(
                      icon: Icons.list_alt_outlined,
                      label: '指标历史',
                      color: Colors.indigo,
                      onTap: () {
                        context.push('/indicators').then((_) {
                          if (mounted) _load(silent: true);
                        });
                      }),
                  _QuickEntry(
                      icon: Icons.event_note_outlined,
                      label: '7天计划',
                      color: Colors.green,
                      onTap: () => context.go('/plan')),
                  _QuickEntry(
                      icon: Icons.insights_outlined,
                      label: '趋势统计',
                      color: Colors.orange,
                      onTap: () => context.go('/stats')),
                  _QuickEntry(
                    icon: _memberStatus.isActive
                        ? Icons.workspace_premium
                        : Icons.workspace_premium_outlined,
                    label: _memberStatus.isActive ? '会员中心' : '升级会员',
                    color: const Color(0xFF0277BD),
                    onTap: () {
                      if (!UserSession.instance.isAccountLogin) {
                        context.push('/login', extra: true);
                      } else {
                        context.push('/membership').then((_) {
                          if (mounted) _load(silent: true);
                        });
                      }
                    },
                  ),
                ],
              );
            }),
          ),
          const SizedBox(height: 14),

          // 最近指标（近 3 天）
          _RecentIndicatorsPanel(
            indicators: _recentIndicators,
            onAdd: () {
              context.push('/indicators/input').then((_) {
                if (mounted) _load(silent: true);
              });
            },
            onViewAll: () => context.push('/indicators'),
          ),
          const SizedBox(height: 14),

          // 最近打卡 + 提醒规则
          LayoutBuilder(builder: (_, c) {
            final wide = c.maxWidth >= 960;
            final clockPanel = _Panel(
              title: '最近打卡',
              action: TextButton(
                  onPressed: () => context.go('/clock'),
                  child: const Text('全部')),
              child: _RecentClockList(
                  records: todayClocks.isNotEmpty
                      ? todayClocks
                      : (data?.clockRecords ?? [])),
            );
            final reminderPanel = _Panel(
              title: '提醒规则',
              action: TextButton(
                  onPressed: () => context.go('/clock'),
                  child: const Text('管理')),
              child: _ReminderPreview(reminders: data?.reminders ?? []),
            );
            if (wide) {
              return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: clockPanel),
                    const SizedBox(width: 12),
                    Expanded(child: reminderPanel),
                  ]);
            }
            return Column(children: [
              clockPanel,
              const SizedBox(height: 12),
              reminderPanel
            ]);
          }),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class _SetupGuideCard extends StatelessWidget {
  const _SetupGuideCard({
    required this.onProfile,
    required this.onIndicator,
    required this.onDemo,
  });

  final VoidCallback onProfile;
  final VoidCallback onIndicator;
  final VoidCallback onDemo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.assignment_ind_outlined,
              color: AppTheme.deepBlue, size: 20),
          SizedBox(width: 8),
          Text(
            '先填写你的健康数据',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
        ]),
        const SizedBox(height: 8),
        const Text(
          '当前还没有可用于分析的数据。完善档案和录入指标后，计划、趋势和会员功能会沿用同一份数据。',
          style: TextStyle(color: AppTheme.muted, fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: 14),
        Wrap(spacing: 10, runSpacing: 10, children: [
          FilledButton.icon(
            onPressed: onProfile,
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('完善档案'),
          ),
          OutlinedButton.icon(
            onPressed: onIndicator,
            icon: const Icon(Icons.add_chart_outlined, size: 18),
            label: const Text('录入指标'),
          ),
          TextButton.icon(
            onPressed: onDemo,
            icon: const Icon(Icons.science_outlined, size: 18),
            label: const Text('使用测试数据'),
          ),
        ]),
      ]),
    );
  }
}

// ── 仪表盘 Hero（进度环 + 今日打卡状态） ────────────────────────
class _DashboardHero extends StatelessWidget {
  const _DashboardHero({
    required this.profile,
    required this.completion,
    required this.doneTypes,
    required this.todayLabel,
    required this.onClockTap,
  });

  final UserProfileData? profile;
  final double completion;
  final Set<String> doneTypes;
  final String todayLabel;
  final VoidCallback onClockTap;

  static const _clockItems = [
    ('meal', '饮食', Icons.restaurant_outlined, Colors.orange),
    ('exercise', '运动', Icons.directions_run_outlined, Colors.green),
    ('medicine', '用药', Icons.medication_outlined, Colors.redAccent),
    ('weight', '称重', Icons.scale_outlined, AppTheme.deepBlue),
  ];

  @override
  Widget build(BuildContext context) {
    final name = (profile?.nickname.isNotEmpty == true)
        ? profile!.nickname
        : UserSession.instance.name;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.deepBlue.withValues(alpha: 0.92),
            const Color(0xFF0288D1)
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(name.isEmpty ? '健康重启计划' : '你好，$name',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(todayLabel,
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 12),
                Text(
                  profile == null ? '请先完善健康档案，开始个性化计划' : '继续保持，稳定打卡是最好的健康投资',
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 13, height: 1.5),
                ),
              ])),
          const SizedBox(width: 16),
          // 进度环
          GestureDetector(
            onTap: onClockTap,
            child: _ProgressRing(value: completion, size: 80),
          ),
        ]),
        const SizedBox(height: 16),
        // 今日打卡四项
        Row(children: [
          for (final item in _clockItems) ...[
            _ClockStatusDot(
              icon: item.$3,
              label: item.$2,
              done: doneTypes.contains(item.$1),
              color: item.$4,
            ),
            if (item != _clockItems.last) const SizedBox(width: 10),
          ],
          const Spacer(),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.white70),
            onPressed: onClockTap,
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Text('去打卡', style: TextStyle(fontSize: 13)),
              Icon(Icons.chevron_right, size: 16),
            ]),
          ),
        ]),
      ]),
    );
  }
}

// ── 圆形进度环 ────────────────────────────────────────────────
class _ProgressRing extends StatelessWidget {
  const _ProgressRing({required this.value, required this.size});
  final double value;
  final double size;

  @override
  Widget build(BuildContext context) {
    final pct = (value * 100).round();
    return SizedBox(
      width: size,
      height: size,
      child: Stack(alignment: Alignment.center, children: [
        CustomPaint(
          size: Size(size, size),
          painter: _RingPainter(value: value),
        ),
        Column(mainAxisSize: MainAxisSize.min, children: [
          Text('$pct%',
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 18)),
          const Text('完成',
              style: TextStyle(color: Colors.white70, fontSize: 10)),
        ]),
      ]),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.value});
  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 5;
    final bgPaint = Paint()
      ..color = Colors.white24
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    final fgPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, bgPaint);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      2 * pi * value,
      false,
      fgPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.value != value;
}

// ── 打卡状态点 ────────────────────────────────────────────────
class _ClockStatusDot extends StatelessWidget {
  const _ClockStatusDot(
      {required this.icon,
      required this.label,
      required this.done,
      required this.color});
  final IconData icon;
  final String label;
  final bool done;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: done ? Colors.white : Colors.white24,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(done ? Icons.check : icon,
            color: done ? color : Colors.white54, size: 18),
      ),
      const SizedBox(height: 4),
      Text(label,
          style: TextStyle(
              color: done ? Colors.white : Colors.white60,
              fontSize: 11,
              fontWeight: FontWeight.w600)),
    ]);
  }
}

// ── 今日关键指标行 ─────────────────────────────────────────────
class _TodayMetricsRow extends StatelessWidget {
  const _TodayMetricsRow({required this.data, required this.onAddIndicator});
  final HealthDashboardData? data;
  final VoidCallback onAddIndicator;

  @override
  Widget build(BuildContext context) {
    final profile = data?.profile;
    final bmi = profile?.bmi ?? 0;
    final latestBp = data?.latestIndicator('bp');
    final latestWeight = data?.latestIndicator('weight');
    final latestGlucose = data?.latestIndicator('glucose');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(
              child: Text('今日数据',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
          TextButton.icon(
            onPressed: onAddIndicator,
            icon: const Icon(Icons.add, size: 15),
            label: const Text('录入', style: TextStyle(fontSize: 13)),
          ),
        ]),
        const SizedBox(height: 10),
        LayoutBuilder(builder: (_, c) {
          final cols = c.maxWidth >= 500 ? 4 : 2;
          return GridView.count(
            crossAxisCount: cols,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: cols == 4 ? 1.7 : 1.5,
            children: [
              _MetricTile(
                  label: 'BMI',
                  value: bmi == 0 ? '--' : bmi.toStringAsFixed(1),
                  sub: profile?.bmiLevel ?? '待完善',
                  icon: Icons.monitor_weight_outlined,
                  color: Colors.teal),
              _MetricTile(
                  label: '血压',
                  value: latestBp?.displayValue ?? '--',
                  sub: latestBp == null
                      ? '未录入'
                      : DateFormat('MM/dd').format(latestBp.measuredTime),
                  icon: Icons.favorite_outline,
                  color: Colors.redAccent),
              _MetricTile(
                  label: '体重',
                  value: latestWeight?.displayValue ?? '--',
                  sub: latestWeight == null
                      ? '未录入'
                      : DateFormat('MM/dd').format(latestWeight.measuredTime),
                  icon: Icons.scale_outlined,
                  color: AppTheme.deepBlue),
              _MetricTile(
                  label: '血糖',
                  value: latestGlucose?.displayValue ?? '--',
                  sub: latestGlucose == null
                      ? '未录入'
                      : DateFormat('MM/dd').format(latestGlucose.measuredTime),
                  icon: Icons.water_drop_outlined,
                  color: Colors.orange),
            ],
          );
        }),
      ]),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile(
      {required this.label,
      required this.value,
      required this.sub,
      required this.icon,
      required this.color});
  final String label;
  final String value;
  final String sub;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(height: 6),
        Text(value,
            style: TextStyle(
                fontWeight: FontWeight.w800, fontSize: 14, color: color),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        Text(sub,
            style: const TextStyle(color: AppTheme.muted, fontSize: 11),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
      ]),
    );
  }
}

// ── 今日计划摘要卡片 ──────────────────────────────────────────
class _TodayPlanCard extends StatelessWidget {
  const _TodayPlanCard(
      {required this.meal,
      required this.exercise,
      required this.onGenerate,
      required this.onViewAll});
  final PlanRecordData? meal;
  final PlanRecordData? exercise;
  final VoidCallback onGenerate;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    final hasPlan = meal != null || exercise != null;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(
              child: Text('今日计划',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
          TextButton(onPressed: onViewAll, child: const Text('全部计划')),
        ]),
        const SizedBox(height: 8),
        if (!hasPlan) ...[
          const Text('暂无今日计划，点击下方按钮生成 7 天方案',
              style: TextStyle(color: AppTheme.muted, fontSize: 13)),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onGenerate,
              icon: const Icon(Icons.auto_awesome_outlined, size: 16),
              label: const Text('生成 7 天计划'),
            ),
          ),
        ] else ...[
          if (meal != null)
            _PlanSummaryRow(
                type: '饮食',
                icon: Icons.restaurant_outlined,
                color: Colors.orange,
                summary: meal!.summary),
          if (meal != null && exercise != null) const SizedBox(height: 8),
          if (exercise != null)
            _PlanSummaryRow(
                type: '运动',
                icon: Icons.directions_run_outlined,
                color: Colors.green,
                summary: exercise!.summary),
        ],
      ]),
    );
  }
}

class _PlanSummaryRow extends StatelessWidget {
  const _PlanSummaryRow(
      {required this.type,
      required this.icon,
      required this.color,
      required this.summary});
  final String type;
  final IconData icon;
  final Color color;
  final String summary;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(width: 10),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('今日$type',
              style: TextStyle(
                  fontWeight: FontWeight.w700, color: color, fontSize: 13)),
          const SizedBox(height: 2),
          Text(summary,
              style: const TextStyle(
                  color: AppTheme.muted, fontSize: 12, height: 1.4),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
        ])),
      ]),
    );
  }
}

// ── 快捷入口按钮 ──────────────────────────────────────────────
class _QuickEntry extends StatelessWidget {
  const _QuickEntry(
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
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 19),
          ),
          const SizedBox(height: 6),
          Text(label,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: color),
              textAlign: TextAlign.center),
        ]),
      ),
    );
  }
}

// ── 最近打卡列表 ──────────────────────────────────────────────
class _RecentClockList extends StatelessWidget {
  const _RecentClockList({required this.records});
  final List<ClockRecordData> records;

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('今日暂无打卡，点击"打卡"标签开始记录。',
            style: TextStyle(color: AppTheme.muted, fontSize: 13)),
      );
    }
    final typeIcon = {
      'meal': Icons.restaurant_outlined,
      'exercise': Icons.directions_run_outlined,
      'medicine': Icons.medication_outlined,
      'weight': Icons.scale_outlined,
      'water': Icons.water_drop_outlined,
    };
    return Column(children: [
      for (final r in records.take(5))
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppTheme.primaryBlue.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(typeIcon[r.type] ?? Icons.check_circle_outline,
                  color: AppTheme.deepBlue, size: 17),
            ),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(r.label,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13)),
                  if (r.note.isNotEmpty)
                    Text(r.note,
                        style: const TextStyle(
                            color: AppTheme.muted, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                ])),
            Text(DateFormat('HH:mm').format(r.clockTime),
                style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
          ]),
        ),
    ]);
  }
}

// ── 提醒预览 ──────────────────────────────────────────────────
class _ReminderPreview extends StatelessWidget {
  const _ReminderPreview({required this.reminders});
  final List<ReminderData> reminders;

  @override
  Widget build(BuildContext context) {
    if (reminders.isEmpty) {
      return const Text('暂无提醒，在打卡页添加。',
          style: TextStyle(color: AppTheme.muted, fontSize: 13));
    }
    return Column(children: [
      for (final r in reminders.take(5))
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppTheme.primaryBlue.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(Icons.notifications_active_outlined,
                  color: AppTheme.deepBlue, size: 17),
            ),
            const SizedBox(width: 10),
            Expanded(
                child: Text(r.label,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13))),
            Text(r.timeText,
                style: const TextStyle(
                    color: AppTheme.deepBlue,
                    fontWeight: FontWeight.w700,
                    fontSize: 13)),
          ]),
        ),
    ]);
  }
}

// ── 最近指标（近 3 天，可收放） ────────────────────────────────
class _RecentIndicatorsPanel extends StatelessWidget {
  const _RecentIndicatorsPanel({
    required this.indicators,
    required this.onAdd,
    required this.onViewAll,
  });

  final List<HealthIndicatorEntry> indicators;
  final VoidCallback onAdd;
  final VoidCallback onViewAll;

  static const _maxShow = 6;

  static const _typeIcon = {
    'weight': (Icons.scale_outlined, Colors.blue),
    'bp': (Icons.favorite_outline, Colors.redAccent),
    'glucose': (Icons.water_drop_outlined, Colors.orange),
    'heart_rate': (Icons.monitor_heart_outlined, Colors.pink),
    'lipid': (Icons.science_outlined, Colors.purple),
    'body_fat': (Icons.person_outlined, Colors.teal),
    'waist': (Icons.straighten_outlined, Colors.brown),
    'spo2': (Icons.air_outlined, Colors.lightBlue),
    'sleep': (Icons.bedtime_outlined, Colors.indigo),
    'steps': (Icons.directions_walk_outlined, Colors.green),
  };

  @override
  Widget build(BuildContext context) {
    final visible = indicators.take(_maxShow).toList();

    return _Panel(
      title: '最近指标',
      action: Row(mainAxisSize: MainAxisSize.min, children: [
        TextButton(onPressed: onViewAll, child: const Text('全部')),
        IconButton(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            iconSize: 18,
            visualDensity: VisualDensity.compact),
      ]),
      child: indicators.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                const Expanded(
                  child: Text('暂无指标记录',
                      style: TextStyle(color: AppTheme.muted, fontSize: 13)),
                ),
                TextButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add, size: 15),
                  label: const Text('录入', style: TextStyle(fontSize: 13)),
                ),
              ]),
            )
          : Column(children: [
              for (final e in visible)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: (_typeIcon[e.type]?.$2 ?? Colors.grey)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(
                        _typeIcon[e.type]?.$1 ?? Icons.monitor_heart_outlined,
                        color: _typeIcon[e.type]?.$2 ?? Colors.grey,
                        size: 17,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(e.label,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 13)),
                          Text(e.displayValue,
                              style: const TextStyle(
                                  color: AppTheme.muted, fontSize: 12)),
                        ])),
                    Text(
                      DateFormat('MM/dd HH:mm').format(e.measuredTime),
                      style:
                          const TextStyle(color: AppTheme.muted, fontSize: 12),
                    ),
                  ]),
                ),
              if (indicators.length > _maxShow)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: GestureDetector(
                    onTap: onViewAll,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: AppTheme.pageBg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '查看全部 ${indicators.length} 条记录',
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.deepBlue,
                                  fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(width: 2),
                            const Icon(Icons.chevron_right,
                                size: 16, color: AppTheme.deepBlue),
                          ]),
                    ),
                  ),
                ),
            ]),
    );
  }
}

// ── 面板容器 ──────────────────────────────────────────────────
class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child, this.action});
  final String title;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800))),
          if (action != null) action!,
        ]),
        const SizedBox(height: 12),
        child,
      ]),
    );
  }
}

extension _IterableX<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

// ── 会员横幅 ──────────────────────────────────────────────────

class _HomeMembershipBanner extends StatelessWidget {
  const _HomeMembershipBanner({required this.status, required this.onTap});
  final MembershipStatus status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (status.isActive) {
      final expiry = DateFormat('yyyy/MM/dd').format(status.expiresAt!);
      return GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0277BD), Color(0xFF0288D1)],
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(children: [
            const Icon(Icons.workspace_premium, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${status.planName ?? '会员版'} · 有效至 $expiry',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white70, size: 18),
          ]),
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF0277BD).withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: const Color(0xFF0277BD).withValues(alpha: 0.25)),
        ),
        child: Row(children: [
          const Icon(Icons.workspace_premium_outlined,
              color: Color(0xFF0277BD), size: 20),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('升级会员',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0277BD))),
                SizedBox(height: 2),
                Text('解锁云同步 · AI方案无限次 · 报告智能识别',
                    style: TextStyle(fontSize: 11, color: AppTheme.muted)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF0277BD),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Text('开通',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
          ),
        ]),
      ),
    );
  }
}
