import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/domain/entities/app_user.dart';
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

  static const authFlow = {splash, signIn, onboarding};
}

/// Роутеру нужно синхронно знать, кто вошёл, прямо в момент редиректа.
/// Читать это из провайдера нельзя: `ref.read` в redirect отдаёт закешированное
/// значение, и после входа редирект видит старый null. Поэтому состояние
/// сессии живёт здесь — обновляется из подписки и сразу дёргает роутер.
class AuthRouterState extends ChangeNotifier {
  AsyncValue<AppUser?> _value = const AsyncValue.loading();

  AsyncValue<AppUser?> get value => _value;

  set value(AsyncValue<AppUser?> next) {
    _value = next;
    notifyListeners();
  }

  bool get isResolving => _value.isLoading && !_value.hasValue;
  AppUser? get user => _value.value;
}

final routerProvider = Provider<GoRouter>((ref) {
  ref.keepAlive();

  final auth = AuthRouterState();
  ref.listen(authStateProvider, (_, next) => auth.value = next,
      fireImmediately: true);
  ref.onDispose(auth.dispose);

  return GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: auth,
    redirect: (context, state) {
      final location = state.matchedLocation;

      if (auth.isResolving) {
        return location == Routes.splash ? null : Routes.splash;
      }

      final user = auth.user;
      if (user == null) {
        return location == Routes.signIn ? null : Routes.signIn;
      }
      if (!user.hasProfile) {
        return location == Routes.onboarding ? null : Routes.onboarding;
      }

      return Routes.authFlow.contains(location) ? Routes.feed : null;
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
