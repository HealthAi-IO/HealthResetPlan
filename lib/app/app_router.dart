import 'package:go_router/go_router.dart';

import '../features/home/home_page.dart';
import '../features/auth/onboarding_page.dart';
import '../features/sync/key_setup_page.dart';

class AppRouter {
  AppRouter._();

  static final GoRouter router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const HomePage(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (_, __) => const OnboardingPage(),
      ),
      GoRoute(
        path: '/sync/key-setup',
        builder: (_, __) => const KeySetupPage(),
      ),
    ],
  );
}
