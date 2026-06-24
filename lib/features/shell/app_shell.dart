import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_theme.dart';
import '../../core/auth/user_session.dart';

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
      label: '我的',
      title: '我的',
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
              IconButton(
                tooltip: '会员中心',
                icon: const Icon(Icons.workspace_premium_outlined),
                onPressed: () {
                  if (!UserSession.instance.isAccountLogin) {
                    context.push('/login', extra: true);
                  } else {
                    context.push('/membership');
                  }
                },
              ),
              PopupMenuButton<String>(
                tooltip: '更多操作',
                onSelected: (value) async {
                  if (value == 'chat') {
                    context.push('/chat');
                  } else if (value == 'report') {
                    context.push('/report');
                  } else if (value == 'membership') {
                    if (!UserSession.instance.isAccountLogin) {
                      context.push('/login', extra: true);
                    } else {
                      context.push('/membership');
                    }
                  } else if (value == 'onboarding') {
                    context.push('/onboarding');
                  } else if (value == 'security') {
                    context.push('/sync');
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'chat', child: Text('AI 健康顾问')),
                  PopupMenuItem(value: 'report', child: Text('报告识别')),
                  PopupMenuItem(value: 'membership', child: Text('会员中心')),
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
