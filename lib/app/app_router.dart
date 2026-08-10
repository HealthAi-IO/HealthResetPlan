import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/user_session.dart';
import '../core/data/health_models.dart';
import '../core/telemetry/telemetry_observer.dart';
import '../features/auth/login_page.dart';
import '../features/auth/register_page.dart';
import '../features/auth/set_password_page.dart';
import '../features/auth/onboarding_page.dart';
import '../features/chat/chat_page.dart' deferred as chat;
import '../features/content/content_detail_page.dart'
    deferred as content_detail;
import '../features/content/content_list_page.dart' deferred as content_list;
import '../features/content/message_center_page.dart' deferred as messages;
import '../features/home/home_page.dart' deferred as home;
import '../features/indicators/indicator_input_page.dart'
    deferred as indicator_input;
import '../features/indicators/indicator_list_page.dart'
    deferred as indicator_list;
import '../features/meals/meal_record_page.dart' deferred as meals;
import '../features/meals/food_hub_page.dart' deferred as food_hub;
import '../features/meals/meal_input_args.dart';
import '../features/plan/plan_page.dart' deferred as plan;
import '../features/profile/profile_page.dart' deferred as profile;
import '../features/records/record_hub_page.dart' deferred as records;
import '../features/quit_smoking/quit_smoking_page.dart'
    deferred as quit_smoking;
import '../features/privacy/privacy_policy_page.dart';
import '../features/report/report_page.dart' deferred as report;
import '../features/self_check/self_check_page.dart' deferred as self_check;
import '../features/shell/app_shell.dart';

class AppRouter {
  AppRouter._();

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static String _safeReturnTo(String? value) {
    if (value == null ||
        !value.startsWith('/') ||
        value.startsWith('/login') ||
        value.startsWith('/register') ||
        value.startsWith('/set-password')) {
      return '/home';
    }
    return value;
  }

  static Page<void> _page(GoRouterState state, Widget child) {
    return CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 160),
      reverseTransitionDuration: const Duration(milliseconds: 120),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutQuad,
          reverseCurve: Curves.easeInQuad,
        );
        return ScaleTransition(
          scale: Tween<double>(begin: 0.995, end: 1).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        );
      },
    );
  }

  static Page<void> _shellPage(GoRouterState state, Widget child) {
    return NoTransitionPage<void>(key: state.pageKey, child: child);
  }

  static final GoRouter router = GoRouter(
    navigatorKey: navigatorKey,
    initialLocation: '/home',
    refreshListenable: UserSession.instance,
    observers: [TelemetryObserver()],
    redirect: (context, state) {
      final path = state.uri.path;
      final authRoute =
          path == '/login' || path == '/register' || path == '/privacy-policy';
      if (!UserSession.instance.isAccountLogin && !authRoute) {
        return Uri(
          path: '/login',
          queryParameters: {
            'account': '1',
            'accountOnly': '1',
            'returnTo': state.uri.toString(),
          },
        ).toString();
      }
      if (UserSession.instance.isAccountLogin && path == '/login') {
        return '/home';
      }
      return null;
    },
    routes: [
      ShellRoute(
        builder: (context, state, child) {
          return AppShell(location: state.uri.path, child: child);
        },
        routes: [
          GoRoute(path: '/', redirect: (_, __) => '/home'),
          GoRoute(
            path: '/home',
            name: '/home',
            pageBuilder: (_, state) => _shellPage(
              state,
              _DeferredPage(
                load: home.loadLibrary,
                builder: () => home.HomePage(),
              ),
            ),
          ),
          GoRoute(
            path: '/profile',
            pageBuilder: (_, state) => _shellPage(
              state,
              _DeferredPage(
                load: profile.loadLibrary,
                builder: () => profile.ProfilePage(
                  manageAiOnOpen: state.uri.queryParameters['manageAi'] == '1',
                  guideProfileOnOpen:
                      state.uri.queryParameters['guideProfile'] == '1',
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/plan',
            name: '/plan',
            pageBuilder: (_, state) => _shellPage(
              state,
              _DeferredPage(
                load: plan.loadLibrary,
                builder: () => plan.PlanPage(),
              ),
            ),
          ),
          GoRoute(
            path: '/records',
            name: '/records',
            pageBuilder: (_, state) => _shellPage(
              state,
              _DeferredPage(
                load: records.loadLibrary,
                builder: () => records.RecordHubPage(
                  initialView: state.uri.queryParameters['view'] ?? 'clock',
                  initialReminderId: int.tryParse(
                    state.uri.queryParameters['reminderId'] ?? '',
                  ),
                  openReminderSettings:
                      state.uri.queryParameters['manage'] == 'rules',
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/meals',
            name: '/meals',
            pageBuilder: (_, state) => _shellPage(
              state,
              _DeferredPage(
                load: food_hub.loadLibrary,
                builder: () => food_hub.FoodHubPage(),
              ),
            ),
          ),
          GoRoute(
            path: '/clock',
            name: '/clock',
            redirect: (_, state) => Uri(
              path: '/records',
              queryParameters: {
                'view': 'clock',
                ...state.uri.queryParameters,
              },
            ).toString(),
          ),
          GoRoute(
            path: '/stats',
            redirect: (_, __) => '/records?view=stats',
          ),
          GoRoute(
            path: '/quit-smoking',
            pageBuilder: (_, state) => _shellPage(
              state,
              _DeferredPage(
                load: quit_smoking.loadLibrary,
                builder: () => quit_smoking.QuitSmokingPage(),
              ),
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/indicators',
        name: '/indicators',
        pageBuilder: (_, state) => _page(
          state,
          _DeferredPage(
            load: indicator_list.loadLibrary,
            builder: () => indicator_list.IndicatorListPage(),
          ),
        ),
      ),
      GoRoute(
        path: '/indicators/input',
        name: '/indicators/input',
        pageBuilder: (_, state) {
          final defaultType = state.extra as String?;
          return _page(
            state,
            _DeferredPage(
              load: indicator_input.loadLibrary,
              builder: () =>
                  indicator_input.IndicatorInputPage(defaultType: defaultType),
            ),
          );
        },
      ),
      GoRoute(
        path: '/indicators/edit/:id',
        pageBuilder: (_, state) {
          final existing = state.extra as HealthIndicatorEntry?;
          return _page(
            state,
            _DeferredPage(
              load: indicator_input.loadLibrary,
              builder: () =>
                  indicator_input.IndicatorInputPage(existing: existing),
            ),
          );
        },
      ),
      GoRoute(
        path: '/meals/input',
        pageBuilder: (_, state) {
          final extra = state.extra;
          return _page(
            state,
            _DeferredPage(
              load: meals.loadLibrary,
              builder: () {
                if (extra is MealRecordData) {
                  return meals.MealRecordPage(record: extra);
                }
                if (extra is MealInputArgs) {
                  return meals.MealRecordPage(
                    mealType: extra.mealType,
                    eatenDate: extra.eatenDate,
                  );
                }
                return meals.MealRecordPage(
                  mealType: extra is String ? extra : 'lunch',
                );
              },
            ),
          );
        },
      ),
      GoRoute(
        path: '/meals/detail/:id',
        pageBuilder: (_, state) {
          final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
          return _page(
            state,
            _DeferredPage(
              load: meals.loadLibrary,
              builder: () => meals.MealDetailPage(id: id),
            ),
          );
        },
      ),
      GoRoute(
        path: '/login',
        pageBuilder: (_, state) {
          final forceAccount = state.extra == true ||
              state.uri.queryParameters['account'] == '1';
          final accountOnly = state.uri.queryParameters['accountOnly'] == '1';
          return _page(
            state,
            LoginPage(
              initialAccountMode: forceAccount,
              accountOnly: accountOnly,
              returnTo: _safeReturnTo(state.uri.queryParameters['returnTo']),
            ),
          );
        },
      ),
      GoRoute(
        path: '/onboarding',
        pageBuilder: (_, state) => _page(state, const OnboardingPage()),
      ),
      GoRoute(
        path: '/report',
        pageBuilder: (_, state) => _page(
          state,
          _DeferredPage(
            load: report.loadLibrary,
            builder: () => report.ReportPage(),
          ),
        ),
      ),
      GoRoute(
        path: '/self-check',
        name: '/self-check',
        pageBuilder: (_, state) => _page(
          state,
          _DeferredPage(
            load: self_check.loadLibrary,
            builder: () => self_check.SelfCheckPage(),
          ),
        ),
      ),
      GoRoute(
        path: '/privacy-policy',
        pageBuilder: (_, state) => _page(state, const PrivacyPolicyPage()),
      ),
      GoRoute(
        path: '/register',
        pageBuilder: (_, state) {
          final args = state.extra;
          return _page(
            state,
            args is RegisterArgs
                ? RegisterPage(args: args)
                : const LoginPage(initialAccountMode: true),
          );
        },
      ),
      GoRoute(
        path: '/set-password',
        pageBuilder: (_, state) => _page(
          state,
          SetPasswordPage(
            returnTo: _safeReturnTo(state.uri.queryParameters['returnTo']),
            allowSkip: state.uri.queryParameters['required'] != '1',
          ),
        ),
      ),
      GoRoute(
        path: '/chat',
        name: '/chat',
        pageBuilder: (_, state) => _page(
          state,
          _DeferredPage(load: chat.loadLibrary, builder: () => chat.ChatPage()),
        ),
      ),
      GoRoute(
        path: '/content',
        pageBuilder: (_, state) => _page(
          state,
          _DeferredPage(
            load: content_list.loadLibrary,
            builder: () => content_list.ContentListPage(),
          ),
        ),
      ),
      GoRoute(
        path: '/content/:id',
        pageBuilder: (_, state) => _page(
          state,
          _DeferredPage(
            load: content_detail.loadLibrary,
            builder: () => content_detail.ContentDetailPage(
              id: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/messages',
        pageBuilder: (_, state) => _page(
          state,
          _DeferredPage(
            load: messages.loadLibrary,
            builder: () => messages.MessageCenterPage(),
          ),
        ),
      ),
    ],
  );
}

class _DeferredPage extends StatefulWidget {
  const _DeferredPage({required this.load, required this.builder});

  final Future<void> Function() load;
  final Widget Function() builder;

  @override
  State<_DeferredPage> createState() => _DeferredPageState();
}

class _DeferredPageState extends State<_DeferredPage> {
  late Future<void> _loading = widget.load();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _loading,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done &&
            !snapshot.hasError) {
          return widget.builder();
        }
        if (snapshot.hasError) {
          return Center(
            child: FilledButton.icon(
              onPressed: () => setState(() => _loading = widget.load()),
              icon: const Icon(Icons.refresh),
              label: const Text('加载失败，点击重试'),
            ),
          );
        }
        return const Center(child: CircularProgressIndicator());
      },
    );
  }
}
