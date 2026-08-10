import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_theme.dart';
import '../../core/auth/user_session.dart';
import '../../core/content/site_message_service.dart';
import '../../core/di/service_locator.dart';

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
      label: '计划',
      path: '/plan',
      icon: Icons.event_note_outlined,
      selectedIcon: Icons.event_note,
    ),
    _TabItem(
      label: '饮食',
      path: '/meals',
      icon: Icons.restaurant_menu_outlined,
      selectedIcon: Icons.restaurant_menu,
    ),
    _TabItem(
      label: '记录',
      path: '/records',
      icon: Icons.fact_check_outlined,
      selectedIcon: Icons.fact_check,
    ),
    _TabItem(
      label: '我的',
      path: '/profile',
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
        final wide = constraints.maxWidth >= 1100;
        final colors = Theme.of(context).colorScheme;
        return Scaffold(
          backgroundColor: AppTheme.pageBg,
          resizeToAvoidBottomInset: false,
          appBar: null,
          body: DecoratedBox(
            decoration: const BoxDecoration(color: AppTheme.pageBg),
            child: wide
                ? Row(
                    children: [
                      _DesktopNavigation(
                        selectedIndex: _index,
                        onDestinationSelected: (value) =>
                            _goTab(context, value),
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            const _DesktopCommandBar(),
                            const Divider(height: 1),
                            Expanded(child: pageHost),
                          ],
                        ),
                      ),
                    ],
                  )
                : SafeArea(
                    top: true,
                    bottom: false,
                    child: pageHost,
                  ),
          ),
          bottomNavigationBar: wide
              ? null
              : defaultTargetPlatform == TargetPlatform.iOS
                  ? CupertinoTabBar(
                      currentIndex: _index,
                      onTap: (value) => _goTab(context, value),
                      activeColor: colors.primary,
                      inactiveColor: AppTheme.muted,
                      backgroundColor: Colors.white.withValues(alpha: 0.94),
                      items: [
                        for (final tab in _tabs)
                          BottomNavigationBarItem(
                            icon: Icon(tab.icon),
                            activeIcon: Icon(tab.selectedIcon),
                            label: tab.label,
                          ),
                      ],
                    )
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
                      indicatorColor: colors.primary.withValues(alpha: 0.14),
                    ),
        );
      },
    );
  }
}

class _DesktopNavigation extends StatelessWidget {
  const _DesktopNavigation({
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      color: Colors.white,
      child: Column(
        children: [
          const SizedBox(
            height: 64,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Icon(Icons.favorite_rounded, size: 22),
                  SizedBox(width: 10),
                  Text(
                    '健康重启计划',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          const SizedBox(height: 14),
          for (var i = 0; i < _AppShellState._tabs.length; i++)
            _NavigationItem(
              label: _AppShellState._tabs[i].label,
              icon: selectedIndex == i
                  ? _AppShellState._tabs[i].selectedIcon
                  : _AppShellState._tabs[i].icon,
              selected: selectedIndex == i,
              onTap: () => onDestinationSelected(i),
            ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Divider(),
          ),
          _NavigationItem(
            label: '报告识别',
            icon: Icons.document_scanner_outlined,
            onTap: () => context.push('/report'),
          ),
          _NavigationItem(
            label: '戒烟计划',
            icon: Icons.smoke_free_outlined,
            onTap: () => context.push('/quit-smoking'),
          ),
          _NavigationItem(
            label: 'AI 健康助手',
            icon: Icons.smart_toy_outlined,
            onTap: () => context.push('/chat'),
          ),
          _NavigationItem(
            label: '健康资讯',
            icon: Icons.auto_stories_outlined,
            onTap: () => context.push('/content'),
          ),
          const Spacer(),
          _NavigationItem(
            label: '账号与数据',
            icon: Icons.account_circle_outlined,
            onTap: () => context.go('/profile'),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _NavigationItem extends StatelessWidget {
  const _NavigationItem({
    required this.label,
    required this.icon,
    required this.onTap,
    this.selected = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: selected ? primary.withValues(alpha: 0.09) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Icon(icon,
                    size: 20, color: selected ? primary : AppTheme.muted),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? primary : AppTheme.ink,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopCommandBar extends StatelessWidget {
  const _DesktopCommandBar();

  @override
  Widget build(BuildContext context) {
    final session = UserSession.instance;
    final displayName = session.name.isEmpty ? '健康用户' : session.name;
    return Container(
      height: 64,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Icon(
            session.isAccountLogin
                ? Icons.cloud_done_outlined
                : Icons.cloud_off,
            size: 18,
            color:
                session.isAccountLogin ? Colors.green.shade600 : AppTheme.muted,
          ),
          const SizedBox(width: 8),
          Text(
            '账号已登录 · 数据自动保存',
            style: const TextStyle(color: AppTheme.muted, fontSize: 13),
          ),
          const Spacer(),
          const _MessageButton(),
          const SizedBox(width: 8),
          CircleAvatar(
            radius: 16,
            child: Text(displayName.characters.first.toUpperCase()),
          ),
          const SizedBox(width: 10),
          Text(displayName,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 4),
          IconButton(
            tooltip: '账号与健康档案',
            onPressed: () => context.go('/profile'),
            icon: const Icon(Icons.chevron_right, size: 20),
          ),
        ],
      ),
    );
  }
}

class _MessageButton extends StatelessWidget {
  const _MessageButton();

  @override
  Widget build(BuildContext context) {
    if (!sl.isRegistered<SiteMessageService>()) {
      return IconButton(
        tooltip: '消息中心',
        onPressed: () => context.push('/messages'),
        icon: const Icon(Icons.notifications_outlined),
      );
    }
    final service = sl<SiteMessageService>();
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) => IconButton(
        tooltip: service.unreadCount == 0
            ? '消息中心'
            : '消息中心，${service.unreadCount}条未读',
        onPressed: () => context.push('/messages'),
        icon: Badge(
          isLabelVisible: service.unreadCount > 0,
          label: Text(
            service.unreadCount > 99 ? '99+' : '${service.unreadCount}',
          ),
          child: const Icon(Icons.notifications_outlined),
        ),
      ),
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
