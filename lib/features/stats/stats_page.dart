import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/app_theme.dart';
import '../../core/auth/user_session.dart';
import '../../core/data/health_models.dart';
import '../../core/data/health_repository.dart';
import '../../core/di/service_locator.dart';
import '../../core/membership/membership_service.dart';
import '../../core/network/auth_api.dart';

class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  final HealthRepository _repo = sl<HealthRepository>();
  final MembershipService _membership = sl<MembershipService>();

  bool _loading = true;
  HealthDashboardData? _data;
  ClockStats? _clockStats;
  String? _error;
  MembershipStatus _memberStatus = MembershipStatus.free;
  AccountInfo? _accountInfo;

  List<HealthIndicatorEntry> _weightEntries = const [];
  List<HealthIndicatorEntry> _bpEntries = const [];
  List<HealthIndicatorEntry> _glucoseEntries = const [];

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
    if (!silent) setState(() { _loading = true; _error = null; });
    try {
      final futures = <Future<Object?>>[
        _repo.loadDashboard(),
        _repo.loadClockStats(),
        _repo.loadIndicators(type: 'weight', limit: 20),
        _repo.loadIndicators(type: 'bp', limit: 20),
        _repo.loadIndicators(type: 'glucose', limit: 20),
        _membership.getStatus().then((s) => s),
      ];
      if (UserSession.instance.isAccountLogin) {
        futures.add(sl<AuthApi>().fetchAccountInfo());
      }
      final results = await Future.wait(futures);
      if (!mounted) return;
      setState(() {
        _data = results[0] as HealthDashboardData;
        _clockStats = results[1] as ClockStats;
        _weightEntries = (results[2] as List<HealthIndicatorEntry>).reversed.toList();
        _bpEntries = (results[3] as List<HealthIndicatorEntry>).reversed.toList();
        _glucoseEntries = (results[4] as List<HealthIndicatorEntry>).reversed.toList();
        _memberStatus = results[5] as MembershipStatus;
        _accountInfo = results.length > 6 ? results[6] as AccountInfo? : null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 40, color: Colors.grey),
            const SizedBox(height: 12),
            const Text('加载失败，下拉刷新重试',
                style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 8),
            TextButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }

    final data = _data;
    if (data == null) return const Center(child: CircularProgressIndicator());
    final profile = data.profile;
    final bmi = profile?.bmi ?? 0;
    final bottomPad = MediaQuery.sizeOf(context).width < 960 ? 100.0 : 20.0;

    void pushInput(String type) {
      context.push('/indicators/input', extra: type).then((_) {
        if (mounted) _load(silent: true);
      });
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPad),
        children: [
          _AccountCard(
            accountInfo: _accountInfo,
            memberStatus: _memberStatus,
            onLogin: () => context.push('/login', extra: true).then((_) {
              if (mounted) _load(silent: true);
            }),
            onMembership: () => context.push('/membership').then((_) {
              if (mounted) _load(silent: true);
            }),
          ),
          const SizedBox(height: 10),
          _UserCard(profile: profile, onEditProfile: () => context.go('/profile')),
          const SizedBox(height: 10),
          _MembershipBanner(
            status: _memberStatus,
            onTap: () {
              // 未登录先引导登录，已登录直接进会员中心
              if (!UserSession.instance.isAccountLogin) {
                context.push('/login', extra: true).then((_) {
                  if (mounted) _load(silent: true);
                });
              } else {
                context.push('/membership').then((_) {
                  if (mounted) _load(silent: true);
                });
              }
            },
          ),
          const SizedBox(height: 14),

          _SummaryRow(profile: profile, data: data),
          const SizedBox(height: 14),

          _Panel(
            title: '打卡完成率',
            subtitle: '日 / 周 / 月 三档统计',
            trailing: TextButton.icon(
              onPressed: () => context.go('/clock'),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('去打卡'),
            ),
            child: _ClockRateSection(stats: _clockStats),
          ),
          const SizedBox(height: 14),

          _Panel(
            title: '体重趋势',
            subtitle: '最近 ${_weightEntries.length} 条  单位：kg  · 触摸查看数据',
            trailing: _AddButton(onTap: () => pushInput('weight')),
            child: _weightEntries.isEmpty
                ? _EmptyChart(text: '暂无体重记录，点击 + 开始录入', onAdd: () => pushInput('weight'))
                : _WeightChart(entries: _weightEntries),
          ),
          const SizedBox(height: 14),

          _Panel(
            title: '血压趋势',
            subtitle: '收缩压（红）/ 舒张压（蓝）mmHg  · 触摸查看数据',
            trailing: _AddButton(onTap: () => pushInput('bp')),
            child: _bpEntries.isEmpty
                ? _EmptyChart(text: '暂无血压记录，点击 + 开始录入', onAdd: () => pushInput('bp'))
                : _BpChart(entries: _bpEntries),
          ),
          const SizedBox(height: 14),

          _Panel(
            title: '血糖趋势',
            subtitle: '空腹 / 餐后  单位：mmol/L  · 触摸查看数据',
            trailing: _AddButton(onTap: () => pushInput('glucose')),
            child: _glucoseEntries.isEmpty
                ? _EmptyChart(text: '暂无血糖记录，点击 + 开始录入', onAdd: () => pushInput('glucose'))
                : _GlucoseChart(entries: _glucoseEntries),
          ),
          const SizedBox(height: 14),

          _Panel(
            title: '最近指标',
            subtitle: '最新 6 项，点全部查看完整记录',
            trailing: TextButton.icon(
              onPressed: () => context.push('/indicators').then((_) {
                if (mounted) _load(silent: true);
              }),
              icon: const Icon(Icons.list_alt_outlined, size: 16),
              label: const Text('全部'),
            ),
            child: _RecentIndicators(
              items: data.indicators,
              bmi: bmi,
              onAdd: () => pushInput('weight'),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

// ── 账号状态卡片 ──────────────────────────────────────────────
class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.accountInfo,
    required this.memberStatus,
    required this.onLogin,
    required this.onMembership,
  });

  final AccountInfo? accountInfo;
  final MembershipStatus memberStatus;
  final VoidCallback onLogin;
  final VoidCallback onMembership;

  @override
  Widget build(BuildContext context) {
    final isLoggedIn = UserSession.instance.isAccountLogin;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: isLoggedIn
            ? const LinearGradient(
                colors: [Color(0xFF2E7D32), Color(0xFF43A047)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : LinearGradient(
                colors: [Colors.orange.shade700, Colors.orange.shade500],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(
              isLoggedIn ? Icons.account_circle : Icons.account_circle_outlined,
              color: Colors.white,
              size: 22,
            ),
            const SizedBox(width: 8),
            Text(
              isLoggedIn ? '已绑定账号' : '尚未绑定账号',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Spacer(),
            if (isLoggedIn)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 8, height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.lightGreenAccent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  const Text('在线',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ]),
              ),
          ]),
          const SizedBox(height: 10),

          if (!isLoggedIn) ...[
            const Text(
              '注册/登录账号后即可使用激活码开通会员，\n享受加密云同步、AI无限次等高级权益。',
              style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onLogin,
                icon: const Icon(Icons.login, size: 18),
                label: const Text('注册 / 登录账号'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.orange.shade700,
                  padding: const EdgeInsets.symmetric(vertical: 11),
                ),
              ),
            ),
          ] else ...[
            // 已登录：展示账号详情
            _AccountDetailRow(
              icon: Icons.fingerprint,
              label: '用户 ID',
              value: _shortId(accountInfo?.userId ?? ''),
            ),
            const SizedBox(height: 6),
            _AccountDetailRow(
              icon: Icons.person_outline,
              label: '昵称',
              value: accountInfo?.nickname.isNotEmpty == true
                  ? accountInfo!.nickname
                  : UserSession.instance.name,
            ),
            const SizedBox(height: 6),
            _AccountDetailRow(
              icon: Icons.cloud_outlined,
              label: '云同步',
              value: (accountInfo?.hasCloudSync == true) ? '已开通' : '未开通',
              valueColor: (accountInfo?.hasCloudSync == true)
                  ? Colors.lightGreenAccent
                  : Colors.white54,
            ),
            const SizedBox(height: 6),
            _AccountDetailRow(
              icon: Icons.workspace_premium,
              label: '会员',
              value: memberStatus.isActive
                  ? '${memberStatus.planName ?? '已开通'}'
                  : '免费版',
              valueColor: memberStatus.isActive
                  ? Colors.lightGreenAccent
                  : Colors.white54,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onMembership,
                icon: const Icon(Icons.workspace_premium_outlined, size: 18),
                label: Text(memberStatus.isActive ? '会员中心' : '开通 / 续费会员'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white54),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _shortId(String id) {
    if (id.length <= 12) return id;
    return '${id.substring(0, 8)}…${id.substring(id.length - 4)}';
  }
}

class _AccountDetailRow extends StatelessWidget {
  const _AccountDetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, size: 15, color: Colors.white60),
      const SizedBox(width: 8),
      Text('$label：',
          style: const TextStyle(color: Colors.white60, fontSize: 13)),
      Expanded(
        child: Text(
          value,
          style: TextStyle(
            color: valueColor ?? Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ]);
  }
}

// ── 用户卡片 ──────────────────────────────────────────────────
class _UserCard extends StatelessWidget {
  const _UserCard({required this.profile, required this.onEditProfile});
  final UserProfileData? profile;
  final VoidCallback onEditProfile;

  @override
  Widget build(BuildContext context) {
    final name = (profile?.nickname.isNotEmpty == true)
        ? profile!.nickname
        : UserSession.instance.name;
    final bmi = profile?.bmi ?? 0;
    final age = profile?.birthYear != null && profile!.birthYear > 0
        ? '${DateTime.now().year - profile!.birthYear} 岁'
        : '';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.deepBlue.withValues(alpha: 0.92), const Color(0xFF0288D1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(children: [
        CircleAvatar(
          radius: 30,
          backgroundColor: Colors.white24,
          child: Text(
            name.isNotEmpty ? name.characters.first : '?',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name.isNotEmpty ? name : '未设置名称',
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Row(children: [
            if (age.isNotEmpty) ...[
              Text(age, style: const TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(width: 10),
            ],
            if (bmi > 0)
              Text('BMI ${bmi.toStringAsFixed(1)}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ]),
        ])),
        TextButton.icon(
          onPressed: onEditProfile,
          icon: const Icon(Icons.edit_outlined, size: 15, color: Colors.white70),
          label: const Text('编辑', style: TextStyle(color: Colors.white70, fontSize: 13)),
        ),
      ]),
    );
  }
}

// ── 概要卡片行 ────────────────────────────────────────────────
class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.profile, required this.data});
  final UserProfileData? profile;
  final HealthDashboardData data;

  @override
  Widget build(BuildContext context) {
    final bmi = profile?.bmi ?? 0;
    final latestWeight = data.latestIndicator('weight');
    final latestBp = data.latestIndicator('bp');
    final todayPct = (data.todayCompletion * 100).round();

    return LayoutBuilder(builder: (_, c) {
      final cols = c.maxWidth >= 600 ? 4 : 2;
      return GridView.count(
        crossAxisCount: cols,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: cols == 4 ? 1.6 : 1.5,
        children: [
          _SummaryCard(title: 'BMI', value: bmi == 0 ? '--' : bmi.toStringAsFixed(1), sub: profile?.bmiLevel ?? '待完善', color: Colors.teal),
          _SummaryCard(title: '最新体重', value: latestWeight?.displayValue ?? '--', sub: latestWeight == null ? '' : DateFormat('MM/dd').format(latestWeight.measuredTime), color: AppTheme.deepBlue),
          _SummaryCard(title: '最新血压', value: latestBp?.displayValue ?? '--', sub: latestBp == null ? '' : DateFormat('MM/dd').format(latestBp.measuredTime), color: Colors.redAccent),
          _SummaryCard(title: '今日完成', value: '$todayPct%', sub: '${data.todayClockCount} 条打卡', color: Colors.orange),
        ],
      );
    });
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.title, required this.value, required this.sub, required this.color});
  final String title;
  final String value;
  final String sub;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(title, style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
        if (sub.isNotEmpty) Text(sub, style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
      ]),
    );
  }
}

// ── 打卡完成率 ────────────────────────────────────────────────
class _ClockRateSection extends StatefulWidget {
  const _ClockRateSection({required this.stats});
  final ClockStats? stats;

  @override
  State<_ClockRateSection> createState() => _ClockRateSectionState();
}

class _ClockRateSectionState extends State<_ClockRateSection> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final stats = widget.stats;
    if (stats == null) return const SizedBox(height: 60, child: Center(child: CircularProgressIndicator()));

    final labels = ['今日', '本周', '本月'];
    final rates = [stats.todayRate, stats.weekRate, stats.monthRate];
    final counts = [stats.today, stats.week, stats.month];
    final days = [stats.todayDays, stats.weekDays, stats.monthDays];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        for (var i = 0; i < labels.length; i++)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => setState(() => _tab = i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                decoration: BoxDecoration(
                  color: _tab == i ? AppTheme.deepBlue : AppTheme.pageBg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(labels[i], style: TextStyle(
                  color: _tab == i ? Colors.white : AppTheme.muted,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                )),
              ),
            ),
          ),
      ]),
      const SizedBox(height: 14),
      _RateBar(rate: rates[_tab], counts: counts[_tab], days: days[_tab]),
    ]);
  }
}

class _RateBar extends StatelessWidget {
  const _RateBar({required this.rate, required this.counts, required this.days});
  final double rate;
  final Map<String, int> counts;
  final int days;

  @override
  Widget build(BuildContext context) {
    final pct = (rate * 100).round();
    const typeInfos = [
      ('meal', '饮食', Colors.orange),
      ('exercise', '运动', Colors.green),
      ('medicine', '用药', Colors.redAccent),
      ('weight', '称重', AppTheme.deepBlue),
      ('water', '饮水', Colors.lightBlue),
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: rate,
              minHeight: 12,
              backgroundColor: AppTheme.pageBg,
              valueColor: AlwaysStoppedAnimation<Color>(
                rate >= 0.8 ? Colors.green : rate >= 0.5 ? Colors.orange : Colors.redAccent,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text('$pct%', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
      ]),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final t in typeInfos)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: t.$3.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: t.$3.withValues(alpha: 0.3)),
            ),
            child: Text('${t.$2} ${counts[t.$1] ?? 0} 次',
                style: TextStyle(color: t.$3, fontWeight: FontWeight.w700, fontSize: 12)),
          ),
      ]),
      const SizedBox(height: 4),
      Text('统计周期：$days 天', style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
    ]);
  }
}

// ── 体重图 ────────────────────────────────────────────────────
class _WeightChart extends StatelessWidget {
  const _WeightChart({required this.entries});
  final List<HealthIndicatorEntry> entries;

  @override
  Widget build(BuildContext context) {
    final values = entries.map((e) => (e.payload['weightKg'] as num?)?.toDouble() ?? 0).toList();
    final dates = entries.map((e) => DateFormat('MM/dd').format(e.measuredTime)).toList();
    return _TouchableLineChart(
      seriesList: [_Series(values: values, color: AppTheme.deepBlue)],
      dates: dates,
      unit: 'kg',
    );
  }
}

// ── 血压双线图 ────────────────────────────────────────────────
class _BpChart extends StatelessWidget {
  const _BpChart({required this.entries});
  final List<HealthIndicatorEntry> entries;

  @override
  Widget build(BuildContext context) {
    final systolic = entries.map((e) => (e.payload['systolic'] as num?)?.toDouble() ?? 0).toList();
    final diastolic = entries.map((e) => (e.payload['diastolic'] as num?)?.toDouble() ?? 0).toList();
    final dates = entries.map((e) => DateFormat('MM/dd').format(e.measuredTime)).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _TouchableLineChart(
        seriesList: [
          _Series(values: systolic, color: Colors.redAccent, label: '收缩压'),
          _Series(values: diastolic, color: AppTheme.deepBlue, label: '舒张压'),
        ],
        dates: dates,
        unit: 'mmHg',
      ),
      const SizedBox(height: 8),
      Row(children: [
        _Legend(color: Colors.redAccent, label: '收缩压'),
        const SizedBox(width: 16),
        _Legend(color: AppTheme.deepBlue, label: '舒张压'),
      ]),
      const SizedBox(height: 4),
      const Text('正常参考：收缩压 <140  舒张压 <90 mmHg',
          style: TextStyle(color: AppTheme.muted, fontSize: 11)),
    ]);
  }
}

// ── 血糖折线图 ────────────────────────────────────────────────
class _GlucoseChart extends StatelessWidget {
  const _GlucoseChart({required this.entries});
  final List<HealthIndicatorEntry> entries;

  @override
  Widget build(BuildContext context) {
    final values = entries.map((e) => (e.payload['glucoseMmol'] as num?)?.toDouble() ?? 0).toList();
    final dates = entries.map((e) => DateFormat('MM/dd').format(e.measuredTime)).toList();
    final mealTypes = entries.map((e) => e.payload['mealType'] as String? ?? 'fasting').toList();
    final fasting = entries.where((e) => (e.payload['mealType'] as String?) != 'postmeal');
    final fastingAvg = fasting.isEmpty ? 0.0
        : fasting.map((e) => (e.payload['glucoseMmol'] as num?)?.toDouble() ?? 0).reduce((a, b) => a + b) / fasting.length;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _TouchableLineChart(
        seriesList: [_Series(values: values, color: Colors.orange)],
        dates: dates,
        unit: 'mmol/L',
        tooltipExtras: mealTypes.map((t) => t == 'postmeal' ? '餐后2h' : t == 'random' ? '随机' : '空腹').toList(),
      ),
      const SizedBox(height: 8),
      Row(children: [
        _Legend(color: Colors.orange, label: '血糖'),
        if (fastingAvg > 0) ...[
          const SizedBox(width: 12),
          Text('空腹均值 ${fastingAvg.toStringAsFixed(1)} mmol/L',
              style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
        ],
      ]),
      const SizedBox(height: 4),
      const Text('正常参考：空腹 3.9-6.1  餐后2h <7.8 mmol/L',
          style: TextStyle(color: AppTheme.muted, fontSize: 11)),
    ]);
  }
}

// ── 可触摸折线图 ──────────────────────────────────────────────
class _TouchableLineChart extends StatefulWidget {
  const _TouchableLineChart({
    required this.seriesList,
    required this.dates,
    required this.unit,
    this.tooltipExtras,
  });

  final List<_Series> seriesList;
  final List<String> dates;
  final String unit;
  final List<String>? tooltipExtras;

  @override
  State<_TouchableLineChart> createState() => _TouchableLineChartState();
}

class _TouchableLineChartState extends State<_TouchableLineChart> {
  int? _selectedIndex;

  static const _padL = 44.0;
  static const _padR = 10.0;

  void _handleTouch(Offset pos) {
    final size = context.size;
    if (size == null) return;
    final n = widget.seriesList.isEmpty ? 0 : widget.seriesList.first.values.length;
    if (n == 0) return;
    final w = size.width - _padL - _padR;
    int closest = 0;
    double minDist = double.infinity;
    for (var i = 0; i < n; i++) {
      final dx = _padL + w * (n == 1 ? 0.5 : i / (n - 1));
      final dist = (dx - pos.dx).abs();
      if (dist < minDist) { minDist = dist; closest = i; }
    }
    if (_selectedIndex != closest) setState(() => _selectedIndex = closest);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (d) => _handleTouch(d.localPosition),
      onPanUpdate: (d) => _handleTouch(d.localPosition),
      child: SizedBox(
        height: 200,
        child: LayoutBuilder(builder: (_, constraints) {
          return Stack(
            clipBehavior: Clip.none,
            children: [
              CustomPaint(
                painter: _LineChartPainter(
                  seriesList: widget.seriesList,
                  dates: widget.dates,
                  unit: widget.unit,
                  selectedIndex: _selectedIndex,
                ),
                size: constraints.biggest,
              ),
              if (_selectedIndex != null)
                _buildTooltip(constraints.maxWidth, _selectedIndex!),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildTooltip(double chartWidth, int idx) {
    if (widget.seriesList.isEmpty) return const SizedBox.shrink();
    final n = widget.seriesList.first.values.length;
    final w = chartWidth - _padL - _padR;
    final dx = _padL + w * (n == 1 ? 0.5 : idx / (n - 1));
    const tooltipW = 118.0;
    final left = (dx - tooltipW / 2).clamp(0.0, chartWidth - tooltipW);
    final date = idx < widget.dates.length ? widget.dates[idx] : '';
    final extra = widget.tooltipExtras != null && idx < widget.tooltipExtras!.length
        ? widget.tooltipExtras![idx]
        : null;

    return Positioned(
      left: left,
      top: 2,
      width: tooltipW,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.cardBorder),
          boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 8, offset: Offset(0, 2))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text(date, style: const TextStyle(color: AppTheme.muted, fontSize: 11, fontWeight: FontWeight.w600)),
              if (extra != null) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppTheme.pageBg,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(extra, style: const TextStyle(color: AppTheme.muted, fontSize: 10)),
                ),
              ],
            ]),
            const SizedBox(height: 3),
            for (final s in widget.seriesList)
              if (idx < s.values.length && s.values[idx] > 0)
                Text(
                  s.label.isEmpty
                      ? '${_fmtVal(s.values[idx])} ${widget.unit}'
                      : '${s.label} ${_fmtVal(s.values[idx])}',
                  style: TextStyle(color: s.color, fontWeight: FontWeight.w800, fontSize: 14),
                ),
          ],
        ),
      ),
    );
  }

  String _fmtVal(double v) => v > 50 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 14, height: 3, color: color),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
    ]);
  }
}

// ── 通用折线图 Painter ────────────────────────────────────────
class _Series {
  const _Series({required this.values, required this.color, this.label = ''});
  final List<double> values;
  final Color color;
  final String label;
}

class _LineChartPainter extends CustomPainter {
  const _LineChartPainter({
    required this.seriesList,
    required this.dates,
    required this.unit,
    this.selectedIndex,
  });
  final List<_Series> seriesList;
  final List<String> dates;
  final String unit;
  final int? selectedIndex;

  @override
  void paint(Canvas canvas, Size size) {
    if (seriesList.isEmpty) return;
    final longest = seriesList.map((s) => s.values.length).reduce(max);
    if (longest == 0) return;

    const padL = 44.0, padR = 10.0, padT = 12.0, padB = 28.0;
    final w = size.width - padL - padR;
    final h = size.height - padT - padB;
    if (w <= 0 || h <= 0) return;

    final allVals = seriesList.expand((s) => s.values).where((v) => v > 0).toList();
    if (allVals.isEmpty) return;
    final minV = allVals.reduce(min);
    final maxV = allVals.reduce(max);
    final span = (maxV - minV) < 0.5 ? 2.0 : (maxV - minV) * 1.15;
    final base = max(0.0, minV - span * 0.05);

    final gridPaint = Paint()..color = AppTheme.cardBorder..strokeWidth = 1;
    const labelStyle = TextStyle(color: AppTheme.muted, fontSize: 10);

    for (var i = 0; i <= 4; i++) {
      final dy = padT + h - h * i / 4;
      canvas.drawLine(Offset(padL, dy), Offset(padL + w, dy), gridPaint);
      final val = base + span * i / 4;
      final tp = TextPainter(
        text: TextSpan(text: val.toStringAsFixed(val > 50 ? 0 : 1), style: labelStyle),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(padL - tp.width - 4, dy - tp.height / 2));
    }

    Offset ptFor(List<double> values, int i) {
      final n = values.length;
      final dx = padL + w * (n == 1 ? 0.5 : i / (n - 1));
      final v = values[i];
      final dy = v <= 0 ? padT + h : padT + h - ((v - base) / span * h).clamp(0.0, h);
      return Offset(dx, dy);
    }

    for (final series in seriesList) {
      final n = series.values.length;
      if (n == 0) continue;

      final linePaint = Paint()
        ..color = series.color
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final fillPaint = Paint()
        ..color = series.color.withValues(alpha: 0.07)
        ..style = PaintingStyle.fill;
      final dotPaint = Paint()..color = series.color..style = PaintingStyle.fill;

      final path = Path()..moveTo(ptFor(series.values, 0).dx, ptFor(series.values, 0).dy);
      for (var i = 1; i < n; i++) { path.lineTo(ptFor(series.values, i).dx, ptFor(series.values, i).dy); }
      canvas.drawPath(path, linePaint);

      final first = ptFor(series.values, 0);
      final last = ptFor(series.values, n - 1);
      final area = Path()
        ..moveTo(first.dx, padT + h)
        ..lineTo(first.dx, first.dy);
      for (var i = 1; i < n; i++) { area.lineTo(ptFor(series.values, i).dx, ptFor(series.values, i).dy); }
      area..lineTo(last.dx, padT + h)..close();
      canvas.drawPath(area, fillPaint);

      for (var i = 0; i < n; i++) {
        canvas.drawCircle(ptFor(series.values, i), 3.2, dotPaint);
      }
    }

    // 选中点高亮
    if (selectedIndex != null) {
      final si = selectedIndex!;
      final n = longest;
      if (si < n) {
        final dx = padL + w * (n == 1 ? 0.5 : si / (n - 1));
        canvas.drawLine(
          Offset(dx, padT),
          Offset(dx, padT + h),
          Paint()..color = AppTheme.muted.withValues(alpha: 0.28)..strokeWidth = 1.5,
        );
        for (final series in seriesList) {
          if (si >= series.values.length || series.values[si] <= 0) continue;
          final p = ptFor(series.values, si);
          canvas.drawCircle(p, 6.5, Paint()..color = Colors.white..style = PaintingStyle.fill);
          canvas.drawCircle(p, 6.5, Paint()..color = series.color..style = PaintingStyle.stroke..strokeWidth = 2.5);
        }
      }
    }

    final n = longest;
    final step = max(1, (n / 5).ceil());
    for (var i = 0; i < n; i += step) {
      if (i >= dates.length) break;
      final dx = padL + w * (n == 1 ? 0.5 : i / (n - 1));
      final tp = TextPainter(
        text: TextSpan(text: dates[i], style: labelStyle),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(dx - tp.width / 2, padT + h + 6));
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter old) =>
      old.selectedIndex != selectedIndex ||
      old.seriesList.length != seriesList.length ||
      (seriesList.isNotEmpty && old.seriesList.isNotEmpty &&
          seriesList.first.values.length != old.seriesList.first.values.length);
}

// ── 空图提示 ──────────────────────────────────────────────────
class _EmptyChart extends StatelessWidget {
  const _EmptyChart({required this.text, required this.onAdd});
  final String text;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 90,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(text, style: const TextStyle(color: AppTheme.muted, fontSize: 13), textAlign: TextAlign.center),
        const SizedBox(height: 8),
        TextButton.icon(onPressed: onAdd, icon: const Icon(Icons.add, size: 16), label: const Text('立即录入')),
      ]),
    );
  }
}

// ── 最近指标列表 ──────────────────────────────────────────────
class _RecentIndicators extends StatelessWidget {
  const _RecentIndicators({required this.items, required this.bmi, required this.onAdd});
  final List<HealthIndicatorEntry> items;
  final double bmi;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Column(children: [
        const Text('暂无数据', style: TextStyle(color: AppTheme.muted)),
        const SizedBox(height: 8),
        TextButton.icon(onPressed: onAdd, icon: const Icon(Icons.add, size: 16), label: const Text('录入指标')),
      ]);
    }
    return Column(children: [
      for (final item in items.take(6))
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppTheme.pageBg, borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_iconFor(item.type), color: AppTheme.deepBlue, size: 19),
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                Text(item.displayValue, style: const TextStyle(color: AppTheme.muted, fontSize: 13)),
              ])),
              Text(DateFormat('MM/dd').format(item.measuredTime),
                  style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
            ]),
          ),
        ),
    ]);
  }
}

// ── 面板容器 ──────────────────────────────────────────────────
class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.subtitle, required this.child, this.trailing});
  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

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
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            Text(subtitle, style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
          ])),
          if (trailing != null) trailing!,
        ]),
        const SizedBox(height: 14),
        child,
      ]),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: const Icon(Icons.add_circle_outline, color: AppTheme.deepBlue),
      tooltip: '录入',
    );
  }
}

IconData _iconFor(String type) => switch (type) {
  'bp' => Icons.favorite_outline,
  'weight' => Icons.scale_outlined,
  'glucose' => Icons.water_drop_outlined,
  'lipid' => Icons.science_outlined,
  'heart_rate' => Icons.monitor_heart_outlined,
  _ => Icons.fiber_manual_record_outlined,
};

// ── 会员横幅 ──────────────────────────────────────────────────
class _MembershipBanner extends StatelessWidget {
  const _MembershipBanner({required this.status, required this.onTap});
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
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${status.planName ?? '会员版'} · 有效至 $expiry',
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.cardBorder),
        ),
        child: Row(children: [
          const Icon(Icons.workspace_premium_outlined, color: AppTheme.deepBlue, size: 18),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              '开通会员 · 解锁云同步、AI无限次等权益',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.ink),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: AppTheme.deepBlue,
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Text('升级', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        ]),
      ),
    );
  }
}
