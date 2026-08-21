import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../core/payment/payment_service.dart';
import '../../core/widgets/motion.dart';
import 'ai_credit_view_data.dart';

class AiBenefitsPage extends StatefulWidget {
  const AiBenefitsPage({super.key});

  @override
  State<AiBenefitsPage> createState() => _AiBenefitsPageState();
}

class _AiBenefitsPageState extends State<AiBenefitsPage> {
  static const _benefits = [
    (
      icon: Icons.document_scanner_outlined,
      title: '报告识别',
      description: '提取检查报告关键指标并整理重点',
      route: '/report'
    ),
    (
      icon: Icons.smart_toy_outlined,
      title: '健康管家 AI',
      description: '结合你的健康记录提供管理参考',
      route: '/chat'
    ),
    (
      icon: Icons.event_note_outlined,
      title: '智能计划',
      description: '生成可执行的饮食、运动与记录建议',
      route: '/plan'
    ),
    (
      icon: Icons.restaurant_menu_outlined,
      title: '餐食分析',
      description: '识别餐食并估算热量与营养信息',
      route: '/meals/input'
    ),
    (
      icon: Icons.auto_graph_outlined,
      title: '健康周报',
      description: '汇总最近一周记录、变化与行动建议',
      route: '/record-history/weekly'
    ),
  ];

  final _service = GetIt.instance<PaymentService>();
  final _benefitsKey = GlobalKey();
  Map<String, dynamic> _balance = const {};
  ({int gifted, int purchased}) _sources = (gifted: 0, purchased: 0);
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final results = await Future.wait([
        _service.balance(),
        _service.ledger(),
      ]).timeout(const Duration(seconds: 8));
      if (!mounted) return;
      final balance = results[0] as Map<String, dynamic>;
      final ledgerSources =
          aiCreditSources(results[1] as List<Map<String, dynamic>>);
      setState(() {
        _balance = balance;
        _sources = (
          gifted: balance.containsKey('gifted_total')
              ? creditIntValue(balance['gifted_total'])
              : ledgerSources.gifted,
          purchased: balance.containsKey('purchased_total')
              ? creditIntValue(balance['purchased_total'])
              : ledgerSources.purchased,
        );
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  void _showBenefits() {
    final target = _benefitsKey.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final balance = creditIntValue(_balance['balance']);
    return Scaffold(
      appBar: AppBar(title: const Text('AI 健康权益')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            MotionFadeSlide(
              child: _CreditOverview(
                loading: _loading,
                failed: _failed,
                balance: balance,
                gifted: _sources.gifted,
                purchased: _sources.purchased,
                consumed: creditIntValue(_balance['consumed_total']),
                onRetry: _load,
              ),
            ),
            const SizedBox(height: 26),
            Text('可使用的 AI 能力',
                key: _benefitsKey,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('每次成功生成扣 1 次，失败不扣次',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 10),
            ..._benefits.map(
              (benefit) => _BenefitRow(
                icon: benefit.icon,
                title: benefit.title,
                description: benefit.description,
                onTap: () => context.push(benefit.route),
              ),
            ),
            const SizedBox(height: 22),
            const _FreeBenefits(),
            const SizedBox(height: 14),
            const _UsageRules(),
            const SizedBox(height: 18),
            Text(
              'AI 内容仅供健康管理参考，不能替代医生诊断或治疗建议。',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 10, 20, 16),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: _failed
              ? FilledButton.icon(
                  key: const ValueKey('retry'),
                  onPressed: _load,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('重新加载权益'),
                )
              : Row(
                  key: ValueKey(balance > 0),
                  children: [
                    if (balance > 0) ...[
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => context.push('/ai-credits'),
                          child: const Text('购买更多次数'),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _loading
                            ? null
                            : balance > 0
                                ? _showBenefits
                                : () => context.push('/ai-credits'),
                        icon: Icon(balance > 0
                            ? Icons.auto_awesome_rounded
                            : Icons.shopping_bag_outlined),
                        label: Text(balance > 0 ? '使用 AI 权益' : '获取 AI 次数'),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _CreditOverview extends StatelessWidget {
  const _CreditOverview({
    required this.loading,
    required this.failed,
    required this.balance,
    required this.gifted,
    required this.purchased,
    required this.consumed,
    required this.onRetry,
  });

  final bool loading;
  final bool failed;
  final int balance;
  final int gifted;
  final int purchased;
  final int consumed;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
          color: colors.primaryContainer,
          borderRadius: BorderRadius.circular(22)),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 240),
        child: failed
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.cloud_off_outlined),
                  const SizedBox(height: 14),
                  Text('权益暂未加载', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  const Text('请检查网络后重试，不会显示估算次数。'),
                  TextButton(onPressed: onRetry, child: const Text('重新加载')),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.auto_awesome_rounded, color: colors.primary),
                      const SizedBox(width: 8),
                      Text('AI 健康权益',
                          style: Theme.of(context).textTheme.titleMedium),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (loading)
                    const LinearProgressIndicator()
                  else ...[
                    Text(
                      '剩余 $balance 次',
                      style:
                          Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: colors.onPrimaryContainer,
                              ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                            child: _CreditMetric(label: '累计赠送', value: gifted)),
                        Expanded(
                            child:
                                _CreditMetric(label: '累计购买', value: purchased)),
                        Expanded(
                            child:
                                _CreditMetric(label: '已使用', value: consumed)),
                      ],
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

class _CreditMetric extends StatelessWidget {
  const _CreditMetric({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 2),
        Text('$value 次', style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}

class _BenefitRow extends StatelessWidget {
  const _BenefitRow(
      {required this.icon,
      required this.title,
      required this.description,
      required this.onTap});

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(14)),
                  child: Icon(icon, color: colors.primary),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(description,
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FreeBenefits extends StatelessWidget {
  const _FreeBenefits();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: colors.secondaryContainer,
          borderRadius: BorderRadius.circular(16)),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.health_and_safety_outlined),
          SizedBox(width: 12),
          Expanded(
              child: Text('基础健康功能永久免费\n健康档案、指标记录、提醒、打卡、基础趋势和历史记录不消耗 AI 次数。')),
        ],
      ),
    );
  }
}

class _UsageRules extends StatelessWidget {
  const _UsageRules();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('次数如何使用'),
          SizedBox(height: 8),
          Text('1. 选择上方任一 AI 能力并提交生成。'),
          SizedBox(height: 5),
          Text('2. 生成成功后统一扣除 1 次；失败不扣次。'),
          SizedBox(height: 5),
          Text('3. 赠送与购买次数共用，永久有效且不自动续费。'),
        ],
      ),
    );
  }
}
