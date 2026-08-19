import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/motion.dart';

class AiBenefitsPage extends StatelessWidget {
  const AiBenefitsPage({super.key});

  static const _benefits = [
    (
      icon: Icons.document_scanner_outlined,
      title: '报告识别',
      description: '协助整理检查报告中的关键指标',
    ),
    (
      icon: Icons.smart_toy_outlined,
      title: '健康管家 AI',
      description: '结合你的健康记录提供管理参考',
    ),
    (
      icon: Icons.event_note_outlined,
      title: '智能计划',
      description: '生成饮食、运动与日常记录建议',
    ),
    (
      icon: Icons.restaurant_menu_outlined,
      title: '餐食分析',
      description: '识别餐食并估算营养信息',
    ),
    (
      icon: Icons.auto_graph_outlined,
      title: '健康周报',
      description: '汇总一周记录与变化趋势',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('AI 健康权益')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.auto_awesome_rounded,
                  size: 34,
                  color: colors.onPrimaryContainer,
                ),
                const SizedBox(height: 18),
                Text(
                  '让每一次记录，\n得到更清晰的分析',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: colors.onPrimaryContainer,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 10),
                Text(
                  '新用户赠送 3 次体验额度，购买次数永久有效，不自动续费。',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.onPrimaryContainer,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Text('权益可用于', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          ..._benefits.map(
            (benefit) => MotionFadeSlide(
              delay: Duration(milliseconds: _benefits.indexOf(benefit) * 45),
              child: _BenefitRow(
                icon: benefit.icon,
                title: benefit.title,
                description: benefit.description,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: colors.secondaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.health_and_safety_outlined,
                  color: colors.onSecondaryContainer,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '基础健康功能永久免费',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: colors.onSecondaryContainer,
                                ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '健康档案、指标记录、提醒、打卡、基础趋势和历史记录不会因次数不足而受限。',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: colors.onSecondaryContainer,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'AI 内容仅供健康管理参考，不能替代医生诊断或治疗建议。',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 10, 20, 16),
        child: FilledButton.icon(
          onPressed: () => context.push('/ai-credits'),
          icon: const Icon(Icons.shopping_bag_outlined),
          label: const Text('查看 AI 次数包'),
        ),
      ),
    );
  }
}

class _BenefitRow extends StatelessWidget {
  const _BenefitRow({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: colors.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(description, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
