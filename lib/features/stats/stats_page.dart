import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/app_theme.dart';
import '../../core/crypto/key_vault.dart';
import '../../core/data/health_models.dart';
import '../../core/data/health_repository.dart';
import '../../core/di/service_locator.dart';

class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  final HealthRepository _repo = sl<HealthRepository>();
  final KeyVault _vault = sl<KeyVault>();

  bool _loading = true;
  HealthDashboardData? _data;
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
    final backed = await _vault.isBackedUp();
    if (!mounted) return;
    setState(() => _syncReady = backed);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final data = _data;
    final profile = data?.profile;
    final latestBp = data?.latestIndicator('bp');
    final latestWeight = data?.latestIndicator('weight');
    final bmi = profile?.bmi ?? 0;
    final trend = data?.weightTrend(limit: 8) ?? const [];
    final bottomPadding =
        MediaQuery.sizeOf(context).width < 960 ? 100.0 : 20.0;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.fromLTRB(20, 20, 20, bottomPadding),
        children: [
          _Panel(
            title: '健康总览',
            subtitle: '汇总本地档案、趋势和提醒完成度',
            child: LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 900 ? 4 : 2;
                return GridView.count(
                  crossAxisCount: columns,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: columns >= 4 ? 1.58 : 1.5,
                  children: [
                    _MetricCard(
                        title: 'BMI',
                        value: bmi == 0 ? '--' : bmi.toStringAsFixed(1)),
                    _MetricCard(
                        title: '最新体重',
                        value: latestWeight?.displayValue ?? '--'),
                    _MetricCard(
                        title: '今日完成',
                        value:
                            '${((data?.todayCompletion ?? 0) * 100).round()}%'),
                    _MetricCard(
                        title: '云同步', value: _syncReady ? '已备份' : '未备份'),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          _Panel(
            title: '当前分析',
            subtitle: '本地规则给出的摘要建议',
            child: Text(
              _riskText(profile, latestBp),
              style: const TextStyle(color: AppTheme.muted, height: 1.6),
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 960;
              final chartPanel = _Panel(
                title: '体重趋势',
                subtitle: '最近 8 条体重记录',
                child: _TrendChart(values: trend),
              );
              final riskPanel = _Panel(
                title: '风险提示',
                subtitle: '基于档案与最近指标的本地规则建议',
                child: _RiskList(
                  bmi: bmi,
                  latestBp: latestBp,
                  syncReady: _syncReady,
                  completion: data?.todayCompletion ?? 0,
                ),
              );
              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: chartPanel),
                    const SizedBox(width: 16),
                    Expanded(flex: 2, child: riskPanel),
                  ],
                );
              }
              return Column(
                children: [
                  chartPanel,
                  const SizedBox(height: 16),
                  riskPanel,
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          _Panel(
            title: '最近指标',
            subtitle: '本地保存的最近健康数据',
            child: _RecentMetrics(items: data?.indicators ?? const []),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  String _riskText(UserProfileData? profile, HealthIndicatorEntry? latestBp) {
    if (profile == null) return '请先完善档案后再查看分析结果。';
    if (latestBp == null) return '已完善档案，建议补充血压记录后再判断风险。';
    final systolic = (latestBp.payload['systolic'] as num?)?.toInt() ?? 0;
    final diastolic = (latestBp.payload['diastolic'] as num?)?.toInt() ?? 0;
    if (systolic >= 140 || diastolic >= 90) {
      return '血压偏高，建议继续低盐饮食、保证睡眠并适当增加有氧运动。';
    }
    if (profile.bmi >= 28) {
      return '体重管理优先级较高，建议保持 1500-1700 kcal 目标并持续记录体重。';
    }
    return '整体状态较平稳，继续保持稳定的饮食、运动和打卡节奏。';
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.pageBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(title,
              style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
          const SizedBox(height: 4),
          Text(value,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _RiskList extends StatelessWidget {
  const _RiskList({
    required this.bmi,
    required this.latestBp,
    required this.syncReady,
    required this.completion,
  });

  final double bmi;
  final HealthIndicatorEntry? latestBp;
  final bool syncReady;
  final double completion;

  @override
  Widget build(BuildContext context) {
    final systolic = (latestBp?.payload['systolic'] as num?)?.toInt() ?? 0;
    final diastolic = (latestBp?.payload['diastolic'] as num?)?.toInt() ?? 0;
    final noRisk = syncReady &&
        completion >= 0.75 &&
        bmi < 28 &&
        (latestBp == null ||
            (((latestBp!.payload['systolic'] as num?)?.toInt() ?? 0) < 140 &&
                ((latestBp!.payload['diastolic'] as num?)?.toInt() ?? 0) < 90));
    final items = <String>[
      if (!syncReady) '主密钥尚未备份，暂不建议开启云同步。',
      if (completion < 0.75) '今日打卡完成度不高，可优先完成饮食、运动和称重。',
      if (bmi >= 28) 'BMI 偏高，建议将计划热量继续控制在合理区间。',
      if (systolic >= 140 || diastolic >= 90) '最近血压偏高，注意低盐与规律运动。',
      if (noRisk) '当前没有明显风险项，继续保持稳定节奏即可。',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final text in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.pageBg,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(text,
                  style: const TextStyle(color: AppTheme.muted, height: 1.5)),
            ),
          ),
      ],
    );
  }
}

class _RecentMetrics extends StatelessWidget {
  const _RecentMetrics({required this.items});

  final List<HealthIndicatorEntry> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Text('暂无数据。', style: TextStyle(color: AppTheme.muted));
    }
    return Column(
      children: [
        for (final item in items.take(8))
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
                    child: Icon(_iconFor(item.type),
                        color: AppTheme.deepBlue, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.label,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(item.displayValue,
                            style: const TextStyle(color: AppTheme.muted)),
                      ],
                    ),
                  ),
                  Text(
                    DateFormat('MM/dd').format(item.measuredTime),
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

class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.values});

  final List<double> values;

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) {
      return const SizedBox(
        height: 160,
        child: Center(
          child: Text('体重记录不足，暂时无法生成趋势图。',
              style: TextStyle(color: AppTheme.muted)),
        ),
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
    const padding = 20.0;
    final width = size.width - padding * 2;
    final height = size.height - padding * 2;
    if (width <= 0 || height <= 0) return;

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
    final fillPaint = Paint()
      ..color = AppTheme.primaryBlue.withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;

    for (var i = 0; i < 3; i++) {
      final dy = padding + height * i / 2;
      canvas.drawLine(
          Offset(padding, dy), Offset(size.width - padding, dy), gridPaint);
    }

    final points = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      final dx =
          padding + width * (values.length == 1 ? 0 : i / (values.length - 1));
      final dy = padding + height - ((values[i] - minValue) / span) * height;
      points.add(Offset(dx, dy));
    }

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }

    canvas.drawPath(path, linePaint);

    final area = Path()
      ..moveTo(points.first.dx, padding + height)
      ..lineTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      area.lineTo(point.dx, point.dy);
    }
    area
      ..lineTo(points.last.dx, padding + height)
      ..close();
    canvas.drawPath(area, fillPaint);
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) =>
      oldDelegate.values != values;
}

IconData _iconFor(String type) {
  return switch (type) {
    'bp' => Icons.favorite_outline,
    'weight' => Icons.scale_outlined,
    'glucose' => Icons.monitor_heart_outlined,
    'lipid' => Icons.science_outlined,
    'heart_rate' => Icons.favorite_border,
    _ => Icons.fiber_manual_record_outlined,
  };
}
