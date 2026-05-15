import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_theme.dart';
import '../../core/data/health_repository.dart';
import '../../core/di/service_locator.dart';

class AppShell extends StatelessWidget {
  const AppShell({
    super.key,
    required this.child,
    required this.location,
  });

  final Widget child;
  final String location;

  static const _tabs = [
    _TabItem(
      label: '首页',
      title: '健康概览',
      path: '/home',
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard,
    ),
    _TabItem(
      label: '档案',
      title: '健康档案',
      path: '/profile',
      icon: Icons.assignment_ind_outlined,
      selectedIcon: Icons.assignment_ind,
    ),
    _TabItem(
      label: '计划',
      title: 'AI 本地计划',
      path: '/plan',
      icon: Icons.event_note_outlined,
      selectedIcon: Icons.event_note,
    ),
    _TabItem(
      label: '打卡',
      title: '提醒与打卡',
      path: '/clock',
      icon: Icons.check_circle_outline,
      selectedIcon: Icons.check_circle,
    ),
    _TabItem(
      label: '统计',
      title: '健康统计',
      path: '/stats',
      icon: Icons.insights_outlined,
      selectedIcon: Icons.insights,
    ),
  ];

  int get _index {
    for (var i = 0; i < _tabs.length; i++) {
      if (location == _tabs[i].path ||
          location.startsWith('${_tabs[i].path}/')) {
        return i;
      }
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final current = _tabs[_index];
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 960;
        return Scaffold(
          appBar: AppBar(
            title: Text(current.title),
            actions: [
              IconButton(
                tooltip: '报告识别',
                icon: const Icon(Icons.document_scanner_outlined),
                onPressed: () => context.push('/report'),
              ),
              IconButton(
                tooltip: '云同步与密钥',
                icon: const Icon(Icons.lock_outline),
                onPressed: () => context.push('/sync/key-setup'),
              ),
              PopupMenuButton<String>(
                tooltip: '更多操作',
                onSelected: (value) async {
                  if (value == 'onboarding') {
                    context.push('/onboarding');
                  } else if (value == 'reset') {
                    await sl<HealthRepository>().resetDemoData();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已恢复本地示例数据')),
                    );
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'onboarding', child: Text('查看引导')),
                  PopupMenuItem(value: 'reset', child: Text('恢复示例数据')),
                ],
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: DecoratedBox(
            decoration: const BoxDecoration(color: AppTheme.pageBg),
            child: wide
                ? Row(
                    children: [
                      NavigationRail(
                        selectedIndex: _index,
                        onDestinationSelected: (value) =>
                            context.go(_tabs[value].path),
                        extended: constraints.maxWidth >= 1180,
                        minExtendedWidth: 184,
                        backgroundColor: Colors.white,
                        indicatorColor:
                            AppTheme.primaryBlue.withValues(alpha: 0.16),
                        selectedIconTheme:
                            const IconThemeData(color: AppTheme.deepBlue),
                        selectedLabelTextStyle: const TextStyle(
                          color: AppTheme.deepBlue,
                          fontWeight: FontWeight.w700,
                        ),
                        destinations: [
                          for (final tab in _tabs)
                            NavigationRailDestination(
                              icon: Icon(tab.icon),
                              selectedIcon: Icon(tab.selectedIcon),
                              label: Text(tab.label),
                            ),
                        ],
                      ),
                      const VerticalDivider(
                          width: 1, color: AppTheme.cardBorder),
                      Expanded(child: child),
                    ],
                  )
                : child,
          ),
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex: _index,
                  onDestinationSelected: (value) =>
                      context.go(_tabs[value].path),
                  destinations: [
                    for (final tab in _tabs)
                      NavigationDestination(
                        icon: Icon(tab.icon),
                        selectedIcon: Icon(tab.selectedIcon),
                        label: tab.label,
                      ),
                  ],
                ),
        );
      },
    );
  }
}

class _TabItem {
  const _TabItem({
    required this.label,
    required this.title,
    required this.path,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final String title;
  final String path;
  final IconData icon;
  final IconData selectedIcon;
}
