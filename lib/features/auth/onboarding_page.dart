import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_theme.dart';

class OnboardingPage extends StatelessWidget {
  const OnboardingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final steps = const [
      _Step(
          icon: Icons.assignment_ind_outlined,
          title: '完善健康档案',
          desc: '填写出生年份、身高、体重、健康目标等基础信息。'),
      _Step(
          icon: Icons.monitor_heart_outlined,
          title: '记录健康数据',
          desc: '记录体重、血压、血糖、饮食和运动，逐步了解身体状态。'),
      _Step(
          icon: Icons.event_note_outlined,
          title: '制定健康计划',
          desc: '根据档案和近期记录生成基础计划，授权后可使用 AI 个性化计划。'),
      _Step(
          icon: Icons.insights_outlined,
          title: '坚持打卡并查看趋势',
          desc: '完成每日健康任务，通过连续记录看见身体变化。'),
      _Step(
          icon: Icons.psychology_outlined,
          title: '使用 AI 健康工具',
          desc: '健康顾问、报告识别、餐食识别和图像分析会在单独授权后启用。'),
    ];
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('使用引导')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: AppTheme.softBlue,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Image.asset(
                  'assets/images/health_reset_logo_transparent.png',
                  width: 72,
                  height: 72,
                ),
                const SizedBox(height: 18),
                const Text(
                  '开始你的健康重启',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                 Text(
                  '从了解自己的身体开始，记录日常变化，逐步建立适合你的健康节奏。',
                  style: TextStyle(color: AppTheme.muted, height: 1.6),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _Pill(text: '账号同步', color: colors.primary),
                    _Pill(text: '加密保护', color: colors.primary),
                    _Pill(text: '长辈模式', color: colors.tertiary),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AppTheme.cardBorder),
            ),
            child: Column(
              children: [
                for (var index = 0; index < steps.length; index++) ...[
                  _StepRow(step: steps[index]),
                  if (index != steps.length - 1)
                    const Divider(indent: 72, endIndent: 16),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => context.go('/home'),
              icon: const Icon(Icons.arrow_forward),
              label: const Text('开始使用'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Step {
  const _Step({
    required this.icon,
    required this.title,
    required this.desc,
  });

  final IconData icon;
  final String title;
  final String desc;
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.step});

  final _Step step;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(step.icon, color: colors.onPrimaryContainer),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(step.title,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(step.desc,
                    style:  TextStyle(color: AppTheme.muted, height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}
