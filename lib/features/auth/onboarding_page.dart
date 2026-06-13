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
          desc: '身高、体重、年龄、病史和用药信息先保存到本地。'),
      _Step(
          icon: Icons.document_scanner_outlined,
          title: '录入体检报告',
          desc: '选择报告图片后，确认关键指标并同步到本地健康库。'),
      _Step(
          icon: Icons.event_note_outlined,
          title: '生成本地计划',
          desc: '系统会基于 BMI 和最近指标生成 7 天饮食与运动方案。'),
      _Step(
          icon: Icons.check_circle_outline,
          title: '开始打卡与提醒',
          desc: '记录饮食、运动、用药和称重，形成完整的健康闭环。'),
      _Step(
          icon: Icons.lock_outline,
          title: '备份主密钥',
          desc: '云同步前完成助记词备份，服务端只保存密文。'),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('使用引导')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.primaryBlue.withValues(alpha: 0.12),
                  Colors.white
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AppTheme.cardBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '开始您的健康重启',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                const Text(
                  '这套客户端优先在本地完成档案、计划、打卡、统计和密钥管理，后续可以无缝接入云同步。',
                  style: TextStyle(color: AppTheme.muted, height: 1.6),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: const [
                    _Pill(text: '本地优先'),
                    _Pill(text: '端到端加密'),
                    _Pill(text: '浅蓝主题'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ...steps.map(
            (step) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _StepCard(step: step),
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

class _StepCard extends StatelessWidget {
  const _StepCard({required this.step});

  final _Step step;

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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(step.icon, color: AppTheme.deepBlue),
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
                    style: const TextStyle(color: AppTheme.muted, height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.pageBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
            fontWeight: FontWeight.w700, color: AppTheme.deepBlue),
      ),
    );
  }
}

