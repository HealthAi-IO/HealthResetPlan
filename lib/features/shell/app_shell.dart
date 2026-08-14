import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_theme.dart';
import '../../app/app_settings_controller.dart';
import '../../core/auth/user_session.dart';
import '../../core/content/site_message_service.dart';
import '../../core/di/service_locator.dart';
import '../../core/network/api_client.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.child,
    required this.location,
    this.navigationShell,
  });

  final Widget child;
  final String location;
  final StatefulNavigationShell? navigationShell;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const _regularTabs = [
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
  ];

  static const _seniorTabs = [
    _TabItem(
      label: '今日',
      path: '/home',
      icon: Icons.home_outlined,
      selectedIcon: Icons.home,
    ),
    _TabItem(
      label: '记录',
      path: '/plan',
      icon: Icons.edit_note_outlined,
      selectedIcon: Icons.edit_note,
    ),
    _TabItem(
      label: '提醒',
      path: '/meals',
      icon: Icons.notifications_outlined,
      selectedIcon: Icons.notifications,
    ),
    _TabItem(
      label: '我的',
      path: '/records',
      icon: Icons.person_outline,
      selectedIcon: Icons.person,
    ),
  ];

  List<_TabItem> get _tabs =>
      appSettingsController.seniorMode ? _seniorTabs : _regularTabs;

  int get _index {
    final branchIndex = widget.navigationShell?.currentIndex;
    if (branchIndex != null) return branchIndex;
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
    final navigationShell = widget.navigationShell;
    if (navigationShell != null) {
      navigationShell.goBranch(value);
      return;
    }
    context.go(_tabs[value].path);
  }

  @override
  Widget build(BuildContext context) {
    final pageHost = widget.child;
    return AnimatedBuilder(
      animation: appSettingsController,
      builder: (context, _) {
        final seniorMode = appSettingsController.seniorMode;
        final tabs = _tabs;
        return LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 720;
            final colors = Theme.of(context).colorScheme;
            return Scaffold(
              backgroundColor: colors.surface,
              resizeToAvoidBottomInset: true,
              appBar: null,
              drawer: wide || seniorMode ? null : const _AppDrawer(),
              drawerEnableOpenDragGesture: !wide && !seniorMode,
              body: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [colors.surfaceContainerLowest, colors.surface],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: wide
                    ? Row(
                        children: [
                          _DesktopNavigation(
                            tabs: tabs,
                            seniorMode: seniorMode,
                            compact: constraints.maxWidth < 1200,
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
                          key: ValueKey(
                            seniorMode
                                ? 'senior-navigation'
                                : 'regular-navigation',
                          ),
                          currentIndex: _index,
                          onTap: (value) => _goTab(context, value),
                          activeColor: colors.primary,
                          inactiveColor: AppTheme.muted,
                          backgroundColor:
                              colors.surface.withValues(alpha: 0.96),
                          items: [
                            for (final tab in tabs)
                              BottomNavigationBarItem(
                                icon: Icon(tab.icon),
                                activeIcon: Icon(tab.selectedIcon),
                                label: tab.label,
                              ),
                          ],
                        )
                      : NavigationBar(
                          key: ValueKey(
                            seniorMode
                                ? 'senior-navigation'
                                : 'regular-navigation',
                          ),
                          selectedIndex: _index,
                          onDestinationSelected: (value) =>
                              _goTab(context, value),
                          destinations: [
                            for (final tab in tabs)
                              NavigationDestination(
                                icon: Icon(tab.icon),
                                selectedIcon: Icon(tab.selectedIcon),
                                label: tab.label,
                              ),
                          ],
                          indicatorColor:
                              colors.primary.withValues(alpha: 0.14),
                        ),
            );
          },
        );
      },
    );
  }
}

class _AppDrawer extends StatelessWidget {
  const _AppDrawer();

  void _open(BuildContext context, String location) {
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.push(location);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final screenWidth = MediaQuery.sizeOf(context).width;
    return Drawer(
      width: (screenWidth * 0.84).clamp(280, 336).toDouble(),
      backgroundColor: colors.surface,
      child: SafeArea(
        child: AnimatedBuilder(
          animation: UserSession.instance,
          builder: (context, _) {
            final session = UserSession.instance;
            final displayName =
                session.name.trim().isEmpty ? '健康用户' : session.name.trim();
            final initial = displayName.characters.first.toUpperCase();
            final avatar = _sessionAvatarProvider();
            return ListView(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
              children: [
                Material(
                  color: colors.primaryContainer.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    onTap: () => _open(context, '/profile'),
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 22,
                            backgroundColor: colors.primary,
                            foregroundColor: colors.onPrimary,
                            foregroundImage: avatar,
                            child: Text(
                              initial,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  session.isAccountLogin
                                      ? '个人中心 · 健康档案'
                                      : '登录后同步健康数据',
                                  style: TextStyle(
                                    color: colors.onSurfaceVariant,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _DrawerSection(
                  title: '智能服务',
                  children: [
                    _DrawerItem(
                      icon: Icons.document_scanner_outlined,
                      label: '报告识别',
                      onTap: () => _open(context, '/report'),
                    ),
                    _DrawerItem(
                      icon: Icons.smart_toy_outlined,
                      label: '健康管家 AI',
                      onTap: () => _open(context, '/chat'),
                    ),
                    _DrawerItem(
                      icon: Icons.image_search_outlined,
                      label: 'AI 健康图像分析',
                      onTap: () => _open(context, '/self-check'),
                    ),
                  ],
                ),
                _DrawerSection(
                  title: '健康工具',
                  children: [
                    _DrawerItem(
                      icon: Icons.list_alt_outlined,
                      label: '指标历史',
                      onTap: () => _open(context, '/indicators'),
                    ),
                    _DrawerItem(
                      icon: Icons.insights_outlined,
                      label: '趋势统计',
                      onTap: () => _open(context, '/records?view=stats'),
                    ),
                    _DrawerItem(
                      icon: Icons.smoke_free_outlined,
                      label: '戒烟计划',
                      onTap: () => _open(context, '/quit-smoking'),
                    ),
                    _DrawerItem(
                      icon: Icons.auto_stories_outlined,
                      label: '健康资讯',
                      onTap: () => _open(context, '/content'),
                    ),
                  ],
                ),
                _DrawerSection(
                  title: '消息与提醒',
                  children: [
                    _DrawerItem(
                      icon: Icons.notifications_outlined,
                      label: '消息中心',
                      onTap: () => _open(context, '/messages'),
                    ),
                    _DrawerItem(
                      icon: Icons.alarm_outlined,
                      label: '提醒设置',
                      onTap: () => _open(context, '/clock?manage=rules'),
                    ),
                  ],
                ),
                _DrawerSection(
                  title: '账户设置',
                  children: [
                    _DrawerItem(
                      icon: Icons.admin_panel_settings_outlined,
                      label: 'AI 数据授权',
                      onTap: () => _open(context, '/profile?manageAi=1'),
                    ),
                    _DrawerItem(
                      icon: Icons.privacy_tip_outlined,
                      label: '隐私政策',
                      onTap: () => _open(context, '/privacy-policy'),
                    ),
                    _DrawerItem(
                      icon: Icons.mail_outline,
                      label: '欢迎信',
                      onTap: () => _open(context, '/welcome-letter'),
                    ),
                  ],
                ),
                if (session.isAccountLogin)
                  TextButton.icon(
                    onPressed: () async {
                      Navigator.of(context).pop();
                      await session.signOut();
                    },
                    icon: const Icon(Icons.logout),
                    label: const Text('退出登录'),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DrawerSection extends StatelessWidget {
  const _DrawerSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
            child: Text(
              title,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      minTileHeight: 48,
      dense: true,
      visualDensity: const VisualDensity(vertical: -1),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      leading: Icon(icon, size: 22, color: colors.primary),
      title: Text(label),
      trailing: Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onTap: onTap,
    );
  }
}

class _DesktopNavigation extends StatelessWidget {
  const _DesktopNavigation({
    required this.tabs,
    required this.seniorMode,
    required this.compact,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final List<_TabItem> tabs;
  final bool seniorMode;
  final bool compact;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: compact ? 176 : 200,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
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
          for (var i = 0; i < tabs.length; i++)
            _NavigationItem(
              label: tabs[i].label,
              icon: selectedIndex == i ? tabs[i].selectedIcon : tabs[i].icon,
              selected: selectedIndex == i,
              onTap: () => onDestinationSelected(i),
            ),
          if (!seniorMode && !compact) ...[
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
              label: '健康管家 AI',
              icon: Icons.smart_toy_outlined,
              onTap: () => context.push('/chat'),
            ),
            _NavigationItem(
              label: '健康资讯',
              icon: Icons.auto_stories_outlined,
              onTap: () => context.push('/content'),
            ),
          ],
          const Spacer(),
          _NavigationItem(
            label: '账号与数据',
            icon: Icons.account_circle_outlined,
            onTap: () => context.push('/profile'),
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
    final avatar = _sessionAvatarProvider();
    return Container(
      height: 64,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
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
            style: TextStyle(color: AppTheme.muted, fontSize: 13),
          ),
          const Spacer(),
          const _MessageButton(),
          const SizedBox(width: 8),
          CircleAvatar(
            radius: 16,
            foregroundImage: avatar,
            child: Text(displayName.characters.first.toUpperCase()),
          ),
          const SizedBox(width: 10),
          Text(displayName,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 4),
          IconButton(
            tooltip: '账号与健康档案',
            onPressed: () => context.push('/profile'),
            icon: const Icon(Icons.chevron_right, size: 20),
          ),
        ],
      ),
    );
  }
}

ImageProvider<Object>? _sessionAvatarProvider() {
  final session = UserSession.instance;
  if (session.avatarUrl.isEmpty) return null;
  final objectKey =
      Uri.tryParse(session.avatarUrl)?.queryParameters['objectKey'];
  final token = session.accessToken;
  if (objectKey == null || objectKey.isEmpty || token == null) return null;
  final baseUrl =
      sl<ApiClient>().dio.options.baseUrl.replaceFirst(RegExp(r'/$'), '');
  return NetworkImage(
    '$baseUrl/files/avatar?objectKey=${Uri.encodeQueryComponent(objectKey)}',
    headers: {'Authorization': 'Bearer $token'},
  );
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
