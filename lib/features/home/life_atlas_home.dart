import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../core/auth/user_session.dart';
import '../../core/data/health_models.dart';
import '../../core/widgets/health_ui.dart';

class LifeAtlasHome extends StatelessWidget {
  const LifeAtlasHome({
    super.key,
    required this.data,
    required this.hasMealRecord,
    required this.bottomPadding,
    required this.onRefresh,
    required this.onMealRecord,
    required this.onAddIndicator,
    required this.onOpenStats,
    required this.onOpenReminders,
  });

  final HealthDashboardData? data;
  final bool hasMealRecord;
  final double bottomPadding;
  final Future<void> Function() onRefresh;
  final VoidCallback onMealRecord;
  final VoidCallback onAddIndicator;
  final VoidCallback onOpenStats;
  final VoidCallback onOpenReminders;

  @override
  Widget build(BuildContext context) {
    final name = UserSession.instance.name.trim();
    final greeting = _greeting();
    final weight = data?.latestIndicator('weight')?.displayValue ?? '--';
    final bp = data?.latestIndicator('bp')?.displayValue ?? '--';
    final recordDays = _recordDays(data?.clockRecords ?? const []);
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: EdgeInsets.fromLTRB(20, 18, 20, bottomPadding),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$greeting，${name.isEmpty ? '朋友' : name}',
                        style: Theme.of(context).textTheme.headlineLarge),
                    const SizedBox(height: 5),
                    const Text('今天从一件对身体有益的小事开始',
                        style: TextStyle(color: AppTheme.muted, fontSize: 14)),
                  ],
                ),
              ),
              const Icon(Icons.more_horiz, color: AppTheme.muted),
            ],
          ),
          const SizedBox(height: 24),
          HealthPanel(
            color: AppTheme.softBlue,
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('现在最值得做',
                      style: TextStyle(
                          color: AppTheme.primaryBlue,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 12),
                Text(hasMealRecord ? '记录一项健康指标' : '记录今天的第一餐',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(hasMealRecord ? '让今天的变化有迹可循' : '拍照或文字记录，约 30 秒',
                    style: const TextStyle(color: AppTheme.muted)),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: hasMealRecord ? onAddIndicator : onMealRecord,
                    icon: const Icon(Icons.add),
                    label: const Text('开始记录'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          const Text('最近的健康信号',
              style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.ink)),
          const SizedBox(height: 12),
          HealthPanel(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Row(
              children: [
                _Metric(label: '体重', value: weight),
                const _MetricDivider(),
                _Metric(label: '血压', value: bp),
                const _MetricDivider(),
                _Metric(
                    label: '连续记录',
                    value: '$recordDays 天',
                    color: AppTheme.leafGreen),
              ],
            ),
          ),
          const SizedBox(height: 27),
          const Text('接下来的照护',
              style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.ink)),
          const SizedBox(height: 14),
          _CareRow(
              label: '现在',
              title: hasMealRecord ? '记录一项健康指标' : '记录第一餐',
              action: '现在',
              onTap: hasMealRecord ? onAddIndicator : onMealRecord,
              color: AppTheme.primaryBlue),
          _CareRow(
              label: '稍后',
              title: '完成今日饮水',
              action: '设置',
              onTap: onOpenReminders,
              color: AppTheme.accentCyan),
          _CareRow(
              label: '晚上',
              title: '回顾今天的记录',
              action: '查看',
              onTap: onOpenStats,
              color: AppTheme.leafGreen,
              last: true),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(
      {required this.label, required this.value, this.color = AppTheme.ink});
  final String label;
  final String value;
  final Color color;
  @override
  Widget build(BuildContext context) => Expanded(
      child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Column(children: [
            Text(label,
                style: const TextStyle(color: AppTheme.muted, fontSize: 14)),
            const SizedBox(height: 8),
            Text(value,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: color, fontSize: 19, fontWeight: FontWeight.w800))
          ])));
}

class _MetricDivider extends StatelessWidget {
  const _MetricDivider();
  @override
  Widget build(BuildContext context) => const SizedBox(
      height: 58, child: VerticalDivider(width: 1, color: AppTheme.cardBorder));
}

class _CareRow extends StatelessWidget {
  const _CareRow(
      {required this.label,
      required this.title,
      required this.action,
      required this.onTap,
      required this.color,
      this.last = false});
  final String label, title, action;
  final VoidCallback onTap;
  final Color color;
  final bool last;
  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        children: [
          SizedBox(
            width: 58,
            child: Column(
              children: [
                Container(
                  width: 18,
                  height: 18,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                if (!last)
                  Expanded(
                      child: Container(width: 2, color: AppTheme.softBlue)),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label,
                            style: const TextStyle(
                                color: AppTheme.muted, fontSize: 13)),
                        const SizedBox(height: 5),
                        Text(title,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: onTap,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(action),
                      const Icon(Icons.chevron_right)
                    ]),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _greeting() {
  final h = DateTime.now().hour;
  if (h < 11) return '早上好';
  if (h < 14) return '中午好';
  if (h < 18) return '下午好';
  return '晚上好';
}

int _recordDays(List<ClockRecordData> records) {
  final days = records.where((r) => r.status == 'done').map((r) {
    final d = r.clockTime;
    return DateTime(d.year, d.month, d.day);
  }).toSet();
  return days.length;
}
