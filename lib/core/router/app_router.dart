import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/providers/auth_providers.dart';
import '../../features/auth/presentation/screens/onboarding_screen.dart';
import '../../features/auth/presentation/screens/sign_in_screen.dart';
import '../../features/create/presentation/create_screen.dart';
import '../../features/discover/presentation/discover_screen.dart';
import '../../features/feed/presentation/feed_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/shell/presentation/home_shell.dart';
import '../widgets/splash_screen.dart';

abstract final class Routes {
  static const splash = '/splash';
  static const signIn = '/sign-in';
  static const onboarding = '/onboarding';
  static const feed = '/feed';
  static const discover = '/discover';
  static const create = '/create';
  static const profile = '/profile';
}

final routerProvider = Provider<GoRouter>((ref) {
  // Роутер создаём один раз; о смене сессии он узнаёт через refreshListenable,
  // а не через пересборку провайдера.
  final refresh = ValueNotifier<int>(0);
  ref.listen(authStateProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) {
      final authState = ref.read(authStateProvider);
      final location = state.matchedLocation;

      if (authState.isLoading && !authState.hasValue) {
        return location == Routes.splash ? null : Routes.splash;
      }

      final user = ref.read(currentUserProvider);
      if (user == null) {
        return location == Routes.signIn ? null : Routes.signIn;
      }
      if (!user.hasProfile) {
        return location == Routes.onboarding ? null : Routes.onboarding;
      }

      const authFlow = {Routes.splash, Routes.signIn, Routes.onboarding};
      return authFlow.contains(location) ? Routes.feed : null;
    },
    routes: [
      GoRoute(
        path: Routes.splash,
        builder: (_, _) => const SplashScreen(),
      ),
      GoRoute(
        path: Routes.signIn,
        builder: (_, _) => const SignInScreen(),
      ),
      GoRoute(
        path: Routes.onboarding,
        builder: (_, _) => const OnboardingScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, _, navigationShell) =>
            HomeShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.feed,
                builder: (_, _) => const FeedScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.discover,
                builder: (_, _) => const DiscoverScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.create,
                builder: (_, _) => const CreateScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.profile,
                builder: (_, _) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
