import 'package:go_router/go_router.dart';

import '../features/auth/onboarding_page.dart';
import '../features/clock/clock_page.dart';
import '../features/home/home_page.dart';
import '../features/plan/plan_page.dart';
import '../features/profile/profile_page.dart';
import '../features/report/report_page.dart';
import '../features/shell/app_shell.dart';
import '../features/stats/stats_page.dart';
import '../features/sync/key_setup_page.dart';

class AppRouter {
  AppRouter._();

  static final GoRouter router = GoRouter(
    initialLocation: '/home',
    routes: [
      ShellRoute(
        builder: (context, state, child) {
          return AppShell(location: state.uri.path, child: child);
        },
        routes: [
          GoRoute(
            path: '/',
            redirect: (_, __) => '/home',
          ),
          GoRoute(
            path: '/home',
            builder: (_, __) => const HomePage(),
          ),
          GoRoute(
            path: '/profile',
            builder: (_, __) => const ProfilePage(),
          ),
          GoRoute(
            path: '/plan',
            builder: (_, __) => const PlanPage(),
          ),
          GoRoute(
            path: '/clock',
            builder: (_, __) => const ClockPage(),
          ),
          GoRoute(
            path: '/stats',
            builder: (_, __) => const StatsPage(),
          ),
        ],
      ),
      GoRoute(
        path: '/onboarding',
        builder: (_, __) => const OnboardingPage(),
      ),
      GoRoute(
        path: '/sync/key-setup',
        builder: (_, __) => const KeySetupPage(),
      ),
      GoRoute(
        path: '/report',
        builder: (_, __) => const ReportPage(),
      ),
    ],
  );
}
