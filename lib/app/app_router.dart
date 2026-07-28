import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/user_session.dart';
import '../core/data/health_models.dart';
import '../core/telemetry/telemetry_observer.dart';
import '../features/auth/login_page.dart';
import '../features/auth/register_page.dart';
import '../features/auth/set_password_page.dart';
import '../features/auth/onboarding_page.dart';
import '../features/chat/chat_page.dart';
import '../features/clock/clock_page.dart';
import '../features/home/home_page.dart';
import '../features/indicators/indicator_input_page.dart';
import '../features/indicators/indicator_list_page.dart';
import '../features/meals/meal_record_page.dart';
import '../features/plan/plan_page.dart';
import '../features/profile/profile_page.dart';
import '../features/privacy/privacy_policy_page.dart';
import '../features/report/report_page.dart';
import '../features/self_check/self_check_page.dart';
import '../features/shell/app_shell.dart';
import '../features/stats/stats_page.dart';

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
            pageBuilder: (_, state) => _shellPage(state, const HomePage()),
          ),
          GoRoute(
            path: '/profile',
            pageBuilder: (_, state) => _shellPage(state, const ProfilePage()),
          ),
          GoRoute(
            path: '/plan',
            name: '/plan',
            pageBuilder: (_, state) => _shellPage(state, const PlanPage()),
          ),
          GoRoute(
            path: '/clock',
            name: '/clock',
            pageBuilder: (_, state) => _shellPage(state, const ClockPage()),
          ),
          GoRoute(
            path: '/stats',
            pageBuilder: (_, state) => _shellPage(state, const StatsPage()),
          ),
        ],
      ),
      GoRoute(
        path: '/indicators',
        name: '/indicators',
        pageBuilder: (_, state) => _page(state, const IndicatorListPage()),
      ),
      GoRoute(
        path: '/indicators/input',
        name: '/indicators/input',
        pageBuilder: (_, state) {
          final defaultType = state.extra as String?;
          return _page(state, IndicatorInputPage(defaultType: defaultType));
        },
      ),
      GoRoute(
        path: '/indicators/edit/:id',
        pageBuilder: (_, state) {
          final existing = state.extra as HealthIndicatorEntry?;
          return _page(state, IndicatorInputPage(existing: existing));
        },
      ),
      GoRoute(
        path: '/meals/input',
        pageBuilder: (_, state) {
          final extra = state.extra;
          if (extra is MealRecordData) {
            return _page(state, MealRecordPage(record: extra));
          }
          if (extra is MealInputArgs) {
            return _page(
              state,
              MealRecordPage(
                mealType: extra.mealType,
                eatenDate: extra.eatenDate,
              ),
            );
          }
          return _page(
            state,
            MealRecordPage(mealType: extra is String ? extra : 'lunch'),
          );
        },
      ),
      GoRoute(
        path: '/meals/detail/:id',
        pageBuilder: (_, state) {
          final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
          return _page(state, MealDetailPage(id: id));
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
        pageBuilder: (_, state) => _page(state, const ReportPage()),
      ),
      GoRoute(
        path: '/self-check',
        name: '/self-check',
        pageBuilder: (_, state) => _page(state, const SelfCheckPage()),
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
        pageBuilder: (_, state) => _page(state, const ChatPage()),
      ),
    ],
  );
}
