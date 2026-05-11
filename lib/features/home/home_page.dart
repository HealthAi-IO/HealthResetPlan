import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_theme.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('健康重启计划'),
        actions: [
          IconButton(
            icon: const Icon(Icons.lock_outline),
            tooltip: '云同步与密钥',
            onPressed: () => context.go('/sync/key-setup'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _GreetingCard(theme: theme),
          const SizedBox(height: 16),
          _ModuleGrid(
            modules: const [
              _Module(icon: Icons.assignment_ind, title: '健康档案', desc: '身高体重病史'),
              _Module(icon: Icons.image_search, title: '报告识别', desc: 'OCR + AI 解读'),
              _Module(icon: Icons.restaurant_menu, title: '饮食计划', desc: 'AI 个性化菜谱'),
              _Module(icon: Icons.directions_run, title: '运动计划', desc: 'AI 个性化训练'),
              _Module(icon: Icons.medication, title: '用药管理', desc: '提醒 + 打卡'),
              _Module(icon: Icons.show_chart, title: '数据趋势', desc: '体重血压血脂'),
              _Module(icon: Icons.bluetooth, title: '可穿戴设备', desc: '体脂秤血压计'),
              _Module(icon: Icons.lock, title: '加密同步', desc: 'AES-256 端到端'),
            ],
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            icon: const Icon(Icons.play_circle_outline),
            label: const Text('开始引导'),
            onPressed: () => context.go('/onboarding'),
          ),
        ],
      ),
    );
  }
}

class _GreetingCard extends StatelessWidget {
  const _GreetingCard({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.healthGreen, AppTheme.techBlue],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '欢迎使用健康重启计划',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '针对三高与肥胖人群的智能管理助手 · 端到端加密',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.92)),
          ),
        ],
      ),
    );
  }
}

class _Module {
  const _Module({required this.icon, required this.title, required this.desc});
  final IconData icon;
  final String title;
  final String desc;
}

class _ModuleGrid extends StatelessWidget {
  const _ModuleGrid({required this.modules});
  final List<_Module> modules;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: modules.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.6,
      ),
      itemBuilder: (context, index) {
        final m = modules[index];
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(m.icon, size: 28, color: AppTheme.healthGreen),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      m.desc,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
