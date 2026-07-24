import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_theme.dart';
import '../../app/theme_controller.dart';
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
      label: '打卡',
      path: '/clock',
      icon: Icons.check_circle_outline,
      selectedIcon: Icons.check_circle,
    ),
    _TabItem(
      label: '趋势',
      path: '/stats',
      icon: Icons.insights_outlined,
      selectedIcon: Icons.insights,
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
          appBar: wide ? null : _mobileAppBar(context),
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
                            _DesktopCommandBar(
                              onThemeTap: () => _showThemePicker(context),
                            ),
                            const Divider(height: 1),
                            Expanded(child: pageHost),
                          ],
                        ),
                      ),
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
                  indicatorColor: colors.primary.withValues(alpha: 0.14),
                ),
        );
      },
    );
  }

  PreferredSizeWidget _mobileAppBar(BuildContext context) {
    return AppBar(
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
            if (value == 'theme') {
              _showThemePicker(context);
            } else if (value == 'onboarding') {
              context.push('/onboarding');
            } else if (value == 'security') {
              context.push('/sync');
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'theme', child: Text('外观主题')),
            PopupMenuItem(value: 'onboarding', child: Text('使用引导')),
            PopupMenuItem(value: 'security', child: Text('云同步与密钥')),
          ],
        ),
        const SizedBox(width: 8),
      ],
    );
  }
}

Future<void> _showThemePicker(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => const _ThemePickerDialog(),
  );
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
            label: 'AI 健康助手',
            icon: Icons.smart_toy_outlined,
            onTap: () => context.push('/chat'),
          ),
          const Spacer(),
          _NavigationItem(
            label: '云同步与密钥',
            icon: Icons.cloud_outlined,
            onTap: () => context.push('/sync'),
          ),
          _NavigationItem(
            label: '外观设置',
            icon: Icons.palette_outlined,
            onTap: () => _showThemePicker(context),
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
  const _DesktopCommandBar({required this.onThemeTap});

  final VoidCallback onThemeTap;

  @override
  Widget build(BuildContext context) {
    final session = UserSession.instance;
    final displayName = session.name.isEmpty ? '本地用户' : session.name;
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
            session.isAccountLogin ? '账号已登录 · 云同步可用' : '本地模式',
            style: const TextStyle(color: AppTheme.muted, fontSize: 13),
          ),
          const Spacer(),
          IconButton(
            tooltip: '外观主题',
            onPressed: onThemeTap,
            icon: const Icon(Icons.palette_outlined),
          ),
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

class _ThemePickerDialog extends StatelessWidget {
  const _ThemePickerDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('外观主题'),
      content: SizedBox(
        width: 420,
        child: AnimatedBuilder(
          animation: themeController,
          builder: (context, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '主题仅保存在当前设备，选择后立即生效。',
                  style: TextStyle(color: AppTheme.muted, fontSize: 13),
                ),
              ),
              const SizedBox(height: 16),
              for (final item in AppColorTheme.values)
                ListTile(
                  onTap: () => themeController.select(item),
                  leading: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: item.seed,
                      shape: BoxShape.circle,
                    ),
                  ),
                  title: Text(item.label),
                  trailing: themeController.colorTheme == item
                      ? Icon(
                          Icons.check_circle,
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : const Icon(Icons.circle_outlined,
                          color: AppTheme.cardBorder),
                ),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('完成'),
        ),
      ],
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
