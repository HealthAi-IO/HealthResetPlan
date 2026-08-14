import 'package:flutter/material.dart';

import '../../../app/app_settings_controller.dart';
import '../../../app/app_theme.dart';

class AuthPageShell extends StatelessWidget {
  const AuthPageShell({
    super.key,
    required this.child,
    this.showBack = false,
  });

  final Widget child;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.pageBg,
      body: Stack(
        children: [
          Positioned(
            top: -110,
            right: -150,
            child: Container(
              width: 390,
              height: 390,
              decoration: BoxDecoration(
                color: AppTheme.softBlue,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const Positioned(
            top: 112,
            right: 48,
            child: _BrandDots(),
          ),
          SafeArea(
            child: Column(
              children: [
                if (showBack)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8, top: 4),
                      child: IconButton(
                        tooltip: '返回',
                        onPressed: () => Navigator.maybePop(context),
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                    ),
                  )
                else
                  const SizedBox(height: 24),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: child,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandDots extends StatelessWidget {
  const _BrandDots();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 38,
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          _Dot(AppTheme.primaryBlue),
          _Dot(AppTheme.accentCyan),
          _Dot(AppTheme.leafGreen),
          _Dot(AppTheme.accentCyan),
          _Dot(AppTheme.leafGreen),
          _Dot(AppTheme.primaryBlue),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot(this.color);
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

class SeniorModeEntry extends StatelessWidget {
  const SeniorModeEntry({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appSettingsController,
      builder: (context, _) {
        final enabled = appSettingsController.seniorMode;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton.outlined(
              tooltip: enabled ? '关闭长辈模式' : '开启长辈模式',
              onPressed: () => appSettingsController.setSeniorMode(!enabled),
              icon: Icon(
                enabled
                    ? Icons.check_circle_rounded
                    : Icons.person_outline_rounded,
              ),
              style: IconButton.styleFrom(
                foregroundColor: enabled
                    ? Theme.of(context).colorScheme.primary
                    : AppTheme.ink,
                backgroundColor: enabled
                    ? AppTheme.softBlue
                    : Theme.of(context).colorScheme.surfaceContainerLow,
                side: BorderSide(color: AppTheme.cardBorder),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              enabled ? '长辈模式已开启' : '长辈模式',
              style: TextStyle(
                color: AppTheme.muted,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        );
      },
    );
  }
}
