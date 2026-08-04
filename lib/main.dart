import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app/app_router.dart';
import 'app/app_messenger.dart';
import 'app/app_theme.dart';
import 'app/theme_controller.dart';
import 'core/ai/ai_plan_generation_controller.dart';
import 'core/auth/user_session.dart';
import 'core/data/health_models.dart';
import 'core/data/health_repository.dart';
import 'core/di/service_locator.dart';
import 'core/content/content_models.dart';
import 'core/content/site_message_service.dart';
import 'core/notification/reminder_scheduler.dart';
import 'core/network/telemetry_api.dart';
import 'core/privacy/privacy_consent_gate.dart';
import 'core/update/app_update_service.dart';

ThemeMode get _themeMode => ThemeMode.light;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await themeController.load();
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
      await setupServiceLocator();

      // 兼容：若无昵称但 profile 有，补一下；不阻塞首屏，后台执行
      if (mounted) setState(() => _ready = true);

      _hydrateUserNameInBackground();
      _initNotificationsInBackground();
      sl<TelemetryApi>().record('app_open');
    } catch (e, stackTrace) {
      debugPrint('App initialization failed: $e');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) setState(() => _initError = '暂时无法连接服务器，请检查网络后重试。');
    }
  }

  /// 用户昵称补全（非首屏关键路径）
  void _hydrateUserNameInBackground() {
    if (UserSession.instance.hasName) return;
    sl<HealthRepository>().loadProfile().then((profile) {
      if (profile != null && profile.nickname.isNotEmpty) {
        UserSession.instance.setName(profile.nickname);
      }
    }).catchError((_) {
      /* 忽略 */
    });
  }

  void _initNotificationsInBackground() {
    final scheduler = sl<ReminderScheduler>();
    scheduler.initialize().then((_) => scheduler.syncAll()).catchError((error) {
      debugPrint('Notification initialization failed: $error');
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_initError != null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        title: '健康重启计划',
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
      final seed = themeController.colorTheme.seed;
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        title: '健康重启计划',
        theme: AppTheme.lightFor(seed),
        darkTheme: AppTheme.dark,
        themeMode: _themeMode,
        home: Scaffold(
          backgroundColor: AppTheme.pageBg,
          body: _SplashContent(accent: seed),
        ),
      );
    }

    return const HealthResetPlanApp();
  }
}

class _SplashContent extends StatelessWidget {
  const _SplashContent({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ColorFiltered(
          colorFilter: ColorFilter.mode(
            accent.withValues(alpha: 0.82),
            BlendMode.color,
          ),
          child: Image.asset(
            'assets/images/splash_trajectory_background.png',
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
          ),
        ),
        SafeArea(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 620),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) => Opacity(
              opacity: value,
              child: Transform.translate(
                offset: Offset(0, 14 * (1 - value)),
                child: child,
              ),
            ),
            child: Column(
              children: [
                const Spacer(flex: 7),
                Image.asset(
                  'assets/images/health_reset_logo.png',
                  width: 108,
                  height: 108,
                  filterQuality: FilterQuality.high,
                ),
                const SizedBox(height: 20),
                const Text(
                  '健康重启计划',
                  style: TextStyle(
                    fontSize: 27,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.ink,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  '记录每一步，看见每一点改变！',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.muted,
                    letterSpacing: 0.35,
                  ),
                ),
                const Spacer(flex: 5),
                const Text(
                  '正在开启你的健康记录',
                  style: TextStyle(
                    color: AppTheme.muted,
                    fontSize: 12,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _SplashDot(color: accent.withValues(alpha: 0.45)),
                    const SizedBox(width: 12),
                    _SplashDot(color: accent),
                    const SizedBox(width: 12),
                    _SplashDot(color: accent.withValues(alpha: 0.68)),
                  ],
                ),
                const Spacer(flex: 2),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SplashDot extends StatelessWidget {
  const _SplashDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: const SizedBox.square(dimension: 7),
    );
  }
}

class HealthResetPlanApp extends StatefulWidget {
  const HealthResetPlanApp({super.key});

  @override
  State<HealthResetPlanApp> createState() => _HealthResetPlanAppState();
}

class _HealthResetPlanAppState extends State<HealthResetPlanApp>
    with WidgetsBindingObserver {
  StreamSubscription<ReminderData>? _reminderSubscription;
  StreamSubscription<int>? _notificationTapSubscription;
  StreamSubscription<SiteMessage>? _siteMessageSubscription;
  late final AiPlanGenerationController _aiPlanController;
  bool _updateChecked = false;
  int _handledAiPlanEventId = 0;
  Timer? _reminderRefreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _aiPlanController = sl<AiPlanGenerationController>();
    _aiPlanController.addListener(_onAiPlanGenerationChanged);
    final scheduler = sl<ReminderScheduler>();
    _reminderSubscription = scheduler.reminderEvents.listen(_showReminder);
    _notificationTapSubscription = scheduler.notificationTapEvents.listen(
      _openReminder,
    );
    final pendingReminderId = scheduler.takePendingNotificationReminderId();
    if (pendingReminderId != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _openReminder(pendingReminderId),
      );
    }
    final siteMessages = sl<SiteMessageService>();
    _siteMessageSubscription = siteMessages.events.listen(_showSiteMessage);
    siteMessages.start();
    _scheduleReminderRefresh();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdate());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _aiPlanController.removeListener(_onAiPlanGenerationChanged);
    _reminderSubscription?.cancel();
    _notificationTapSubscription?.cancel();
    _siteMessageSubscription?.cancel();
    _reminderRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      sl<SiteMessageService>().poll();
      sl<ReminderScheduler>().syncAll().catchError((error) {
        debugPrint('Reminder refresh failed: $error');
      });
      _scheduleReminderRefresh();
    }
  }

  void _scheduleReminderRefresh() {
    _reminderRefreshTimer?.cancel();
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    _reminderRefreshTimer = Timer(
      tomorrow.difference(now) + const Duration(seconds: 1),
      () {
        sl<ReminderScheduler>().syncAll().catchError((error) {
          debugPrint('Reminder refresh failed: $error');
        });
        _scheduleReminderRefresh();
      },
    );
  }

  void _showSiteMessage(SiteMessage message) {
    appMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(message.title),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: '查看',
          onPressed: () async {
            await sl<SiteMessageService>().markRead(message.id);
            final contentId = message.contentId;
            if (contentId != null && message.contentStatus == 'published') {
              AppRouter.router.push('/content/$contentId');
            } else {
              AppRouter.router.push('/messages');
            }
          },
        ),
      ),
    );
  }

  void _onAiPlanGenerationChanged() {
    if (_aiPlanController.eventId == _handledAiPlanEventId) return;
    _handledAiPlanEventId = _aiPlanController.eventId;
    final currentPath =
        AppRouter.router.routeInformationProvider.value.uri.path;
    if (currentPath == '/plan') return;

    if (_aiPlanController.status == AiPlanGenerationStatus.completed) {
      appMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: const Text('AI 健康计划已生成'),
          action: SnackBarAction(
            label: '查看',
            onPressed: () => AppRouter.router.go('/plan'),
          ),
        ),
      );
    } else if (_aiPlanController.status == AiPlanGenerationStatus.failed) {
      appMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: const Text('AI 健康计划生成失败'),
          action: SnackBarAction(
            label: '返回计划',
            onPressed: () => AppRouter.router.go('/plan'),
          ),
        ),
      );
    }
  }

  void _showReminder(ReminderData reminder) {
    final note = reminder.payload['note'] as String? ?? '';
    final body = note.isNotEmpty ? note : reminder.label;
    appMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(body),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: '查看',
          onPressed: () {
            final id = reminder.id;
            if (id != null) _openReminder(id);
          },
        ),
      ),
    );
  }

  void _openReminder(int reminderId) {
    AppRouter.router.go('/clock?reminderId=$reminderId');
  }

  Future<void> _checkForUpdate() async {
    if (_updateChecked) return;
    _updateChecked = true;

    final update = await AppUpdateService(client: sl()).check();
    if (!mounted || update == null) return;

    final context = AppRouter.navigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: !update.forceUpdate,
      builder: (dialogContext) => PopScope(
        canPop: !update.forceUpdate,
        child: AlertDialog(
          title: Text('发现新版本 v${update.latestVersion}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (update.releaseNotes.isNotEmpty) Text(update.releaseNotes),
              if (update.packageSizeMb != null) ...[
                const SizedBox(height: 12),
                Text(
                  '安装包大小：${update.packageSizeMb} MB',
                  style: Theme.of(dialogContext).textTheme.bodySmall,
                ),
              ],
            ],
          ),
          actions: [
            if (!update.forceUpdate)
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('稍后提醒'),
              ),
            FilledButton(
              onPressed: () => _openUpdate(update.packageUrl),
              child: const Text('立即更新'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openUpdate(String packageUrl) async {
    if (!isTrustedPackageUrl(packageUrl)) {
      appMessengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('更新地址未通过安全校验')),
      );
      return;
    }
    final opened = await launchUrl(
      Uri.parse(packageUrl),
      mode: LaunchMode.externalApplication,
    );
    if (!opened) {
      appMessengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('无法打开下载地址，请稍后重试')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeController,
      builder: (context, _) => MaterialApp.router(
        scaffoldMessengerKey: appMessengerKey,
        title: '健康重启计划',
        theme: AppTheme.lightFor(themeController.colorTheme.seed),
        darkTheme: AppTheme.dark,
        themeMode: _themeMode,
        routerConfig: AppRouter.router,
        debugShowCheckedModeBanner: false,
        supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
      ),
    );
  }
}
