import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_theme.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.child,
    required this.location,
  });

  final Widget child;
  final String location;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const _tabs = [
    _TabItem(
      label: '首页',
      path: '/home',
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard,
    ),
    _TabItem(
      label: '档案',
      path: '/profile',
      icon: Icons.assignment_ind_outlined,
      selectedIcon: Icons.assignment_ind,
    ),
    _TabItem(
      label: '计划',
      path: '/plan',
      icon: Icons.event_note_outlined,
      selectedIcon: Icons.event_note,
    ),
    _TabItem(
      label: '打卡',
      path: '/clock',
      icon: Icons.check_circle_outline,
      selectedIcon: Icons.check_circle,
    ),
    _TabItem(
      label: '我的',
      path: '/stats',
      icon: Icons.person_outline,
      selectedIcon: Icons.person,
    ),
  ];

  int get _index {
    for (var i = 0; i < _tabs.length; i++) {
      if (widget.location == _tabs[i].path ||
          widget.location.startsWith('${_tabs[i].path}/')) {
        return i;
      }
    }
    return 0;
  }

  void _goTab(BuildContext context, int value) {
    if (value == _index) return;
    context.go(_tabs[value].path);
  }

  @override
  Widget build(BuildContext context) {
    final pageHost = RepaintBoundary(child: widget.child);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 960;
        return Scaffold(
          backgroundColor: AppTheme.pageBg,
          resizeToAvoidBottomInset: false,
          appBar: AppBar(
            title: const Text('健康重启计划'),
            actions: [
              IconButton(
                tooltip: '报告识别',
                icon: const Icon(Icons.document_scanner_outlined),
                onPressed: () => context.push('/report'),
              ),
              IconButton(
                tooltip: 'AI 健康顾问',
                icon: const Icon(Icons.psychology_outlined),
                onPressed: () => context.push('/chat'),
              ),
              PopupMenuButton<String>(
                tooltip: '更多操作',
                onSelected: (value) {
                  if (value == 'chat') {
                    context.push('/chat');
                  } else if (value == 'report') {
                    context.push('/report');
                  } else if (value == 'self-check') {
                    context.push('/self-check');
                  } else if (value == 'weather') {
                    context.push('/weather');
                  } else if (value == 'onboarding') {
                    context.push('/onboarding');
                  } else if (value == 'security') {
                    context.push('/sync');
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'chat', child: Text('AI 健康顾问')),
                  PopupMenuItem(value: 'report', child: Text('报告识别')),
                  PopupMenuItem(value: 'self-check', child: Text('AI 拍照自查')),
                  PopupMenuItem(value: 'weather', child: Text('天气')),
                  PopupMenuItem(value: 'onboarding', child: Text('使用引导')),
                  PopupMenuItem(value: 'security', child: Text('数据安全与密钥')),
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
                            _goTab(context, value),
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
                        width: 1,
                        color: AppTheme.cardBorder,
                      ),
                      Expanded(child: pageHost),
                    ],
                  )
                : pageHost,
          ),
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex: _index,
                  onDestinationSelected: (value) => _goTab(context, value),
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
    required this.path,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final String path;
  final IconData icon;
  final IconData selectedIcon;
}
