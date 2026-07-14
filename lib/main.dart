import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app/app_router.dart';
import 'app/app_theme.dart';
import 'core/auth/user_session.dart';
import 'core/data/health_models.dart';
import 'core/data/health_repository.dart';
import 'core/di/service_locator.dart';
import 'core/notification/reminder_scheduler.dart';
import 'core/privacy/privacy_consent_gate.dart';

ThemeMode get _themeMode => ThemeMode.light;
final GlobalKey<ScaffoldMessengerState> _messengerKey =
    GlobalKey<ScaffoldMessengerState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PrivacyConsentGate(child: _AppLoader()));
}

class _AppLoader extends StatefulWidget {
  const _AppLoader();

  @override
  State<_AppLoader> createState() => _AppLoaderState();
}

class _AppLoaderState extends State<_AppLoader> {
  bool _ready = false;
  String? _initError;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    if (mounted) setState(() => _initError = null);
    try {
      // setupServiceLocator 内部已并行执行 UserSession.load + DB 初始化
      await setupServiceLocator();

      // 兼容：若无昵称但 profile 有，补一下；不阻塞首屏，后台执行
      if (mounted) setState(() => _ready = true);

      _hydrateUserNameInBackground();
      _initNotificationsInBackground();
    } catch (e) {
      if (mounted) setState(() => _initError = e.toString());
    }
  }

  /// 用户昵称补全（非首屏关键路径）
  void _hydrateUserNameInBackground() {
    if (UserSession.instance.hasName) return;
    sl<HealthRepository>().loadProfile().then((profile) {
      if (profile != null && profile.nickname.isNotEmpty) {
        UserSession.instance.setName(profile.nickname);
      }
    }).catchError((_) {/* 忽略 */});
  }

  void _initNotificationsInBackground() {
    final scheduler = sl<ReminderScheduler>();
    scheduler.initialize().then((_) => scheduler.syncAll()).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    if (_initError != null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: _themeMode,
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  const Text(
                    '启动失败',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _initError!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(onPressed: _init, child: const Text('重试')),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (!_ready) {
      // 启动闪屏：品牌色背景 + Logo + Loading
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: _themeMode,
        home: Scaffold(
          backgroundColor: const Color(0xFFF5F8FF),
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF03A9F4), Color(0xFF0288D1)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF03A9F4).withValues(alpha: 0.3),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.favorite_rounded,
                      color: Colors.white, size: 46),
                ),
                const SizedBox(height: 18),
                const Text(
                  '健康重启计划',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1A1A2E),
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 32),
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return const HealthResetPlanApp();
  }
}

class HealthResetPlanApp extends StatefulWidget {
  const HealthResetPlanApp({super.key});

  @override
  State<HealthResetPlanApp> createState() => _HealthResetPlanAppState();
}

class _HealthResetPlanAppState extends State<HealthResetPlanApp> {
  StreamSubscription<ReminderData>? _reminderSubscription;

  @override
  void initState() {
    super.initState();
    _reminderSubscription =
        sl<ReminderScheduler>().reminderEvents.listen(_showReminder);
  }

  @override
  void dispose() {
    _reminderSubscription?.cancel();
    super.dispose();
  }

  void _showReminder(ReminderData reminder) {
    final note = reminder.payload['note'] as String? ?? '';
    final body = note.isNotEmpty ? note : reminder.label;
    _messengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(body),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(label: 'OK', onPressed: () {}),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      scaffoldMessengerKey: _messengerKey,
      title: '健康重启计划',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: _themeMode,
      routerConfig: AppRouter.router,
      debugShowCheckedModeBanner: false,
      supportedLocales: const [
        Locale('zh', 'CN'),
        Locale('en', 'US'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}
