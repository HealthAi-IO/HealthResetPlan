import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app/app_router.dart';
import 'app/app_theme.dart';
import 'core/auth/user_session.dart';
import 'core/data/health_repository.dart';
import 'core/di/service_locator.dart';
import 'core/notification/reminder_scheduler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 立即 runApp，避免初始化耗时导致白屏；真正的初始化在 _AppLoader 内异步完成
  runApp(const _AppLoader());
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
      await setupServiceLocator();
      await UserSession.instance.load();
      // 兼容已有用户：若本地无名称但 profile 已有 nickname，同步过来
      if (!UserSession.instance.hasName) {
        final profile = await sl<HealthRepository>().loadProfile();
        if (profile != null && profile.nickname.isNotEmpty) {
          await UserSession.instance.setName(profile.nickname);
        }
      }
      if (mounted) setState(() => _ready = true);
      // 通知初始化不阻塞启动：EMUI / HarmonyOS 等设备的 platform channel 可能延迟
      _initNotificationsInBackground();
    } catch (e) {
      if (mounted) setState(() => _initError = e.toString());
    }
  }

  void _initNotificationsInBackground() {
    final scheduler = sl<ReminderScheduler>();
    scheduler
        .initialize()
        .then((_) => scheduler.requestPermission())
        .then((_) => scheduler.syncAll())
        .catchError((_) {}); // 失败静默忽略，不影响核心功能
  }

  @override
  Widget build(BuildContext context) {
    if (_initError != null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.system,
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
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.system,
        home: const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    return const HealthResetPlanApp();
  }
}

class HealthResetPlanApp extends StatelessWidget {
  const HealthResetPlanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '健康重启计划',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
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
