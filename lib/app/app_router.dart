import 'package:go_router/go_router.dart';

import '../core/auth/user_session.dart';
import '../core/data/health_models.dart';
import '../features/auth/login_page.dart';
import '../features/auth/onboarding_page.dart';
import '../features/clock/clock_page.dart';
import '../features/home/home_page.dart';
import '../features/indicators/indicator_input_page.dart';
import '../features/indicators/indicator_list_page.dart';
import '../features/plan/plan_page.dart';
import '../features/profile/profile_page.dart';
import '../features/report/report_page.dart';
import '../features/shell/app_shell.dart';
import '../features/stats/stats_page.dart';
import '../features/chat/chat_page.dart';
import '../features/membership/membership_page.dart';
import '../features/sync/cloud_sync_page.dart';
import '../features/sync/key_setup_page.dart';

class AppRouter {
  AppRouter._();

  static final GoRouter router = GoRouter(
    initialLocation: '/home',
    redirect: (context, state) {
      final path = state.uri.path;
      if (!UserSession.instance.hasName && path != '/login') return '/login';
      return null;
    },
    routes: [
      ShellRoute(
        builder: (context, state, child) {
          return AppShell(location: state.uri.path, child: child);
        },
        routes: [
          GoRoute(path: '/', redirect: (_, __) => '/home'),
          GoRoute(path: '/home', builder: (_, __) => const HomePage()),
          GoRoute(path: '/profile', builder: (_, __) => const ProfilePage()),
          GoRoute(path: '/plan', builder: (_, __) => const PlanPage()),
          GoRoute(path: '/clock', builder: (_, __) => const ClockPage()),
          GoRoute(path: '/stats', builder: (_, __) => const StatsPage()),
        ],
      ),
      // 健康指标
      GoRoute(
        path: '/indicators',
        builder: (_, __) => const IndicatorListPage(),
      ),
      GoRoute(
        path: '/indicators/input',
        builder: (_, state) {
          final defaultType = state.extra as String?;
          return IndicatorInputPage(defaultType: defaultType);
        },
      ),
      GoRoute(
        path: '/indicators/edit/:id',
        builder: (_, state) {
          final existing = state.extra as HealthIndicatorEntry?;
          return IndicatorInputPage(existing: existing);
        },
      ),
      // 其他
      GoRoute(path: '/login', builder: (_, __) => const LoginPage()),
      GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingPage()),
      GoRoute(path: '/sync', builder: (_, __) => const CloudSyncPage()),
      GoRoute(path: '/sync/key-setup', builder: (_, __) => const KeySetupPage()),
      GoRoute(path: '/report', builder: (_, __) => const ReportPage()),
      GoRoute(path: '/membership', builder: (_, __) => const MembershipPage()),
      GoRoute(path: '/chat', builder: (_, __) => const ChatPage()),
    ],
  );
}
