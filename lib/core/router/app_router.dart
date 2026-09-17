import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../config/feature_flags.dart';

import '../../features/auth/domain/entities/app_user.dart';
import '../../features/chat/presentation/chat_screen.dart';
import '../../features/chat/presentation/conversations_screen.dart';
import '../../features/auth/presentation/providers/auth_providers.dart';
import '../../features/auth/presentation/screens/onboarding_screen.dart';
import '../../features/auth/presentation/screens/sign_in_screen.dart';
import '../../features/create/presentation/create_screen.dart';
import '../../features/discover/presentation/discover_screen.dart';
import '../../features/events/presentation/events_screen.dart';
import '../../features/feed/domain/entities/post.dart';
import '../../features/feed/presentation/feed_screen.dart';
import '../../features/feed/presentation/post_detail_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/routes/presentation/route_detail_screen.dart';
import '../../features/routes/presentation/route_recorder_screen.dart';
import '../../features/shell/presentation/home_shell.dart';
import '../widgets/splash_screen.dart';

abstract final class Routes {
  static const splash = '/splash';
  static const signIn = '/sign-in';
  static const onboarding = '/onboarding';
  static const feed = '/feed';
  static const discover = '/discover';
  static const events = '/events';
  static const create = '/create';
  static const chats = '/chats';
  static const profile = '/profile';

  /// Запись и просмотр маршрутов живут вне вкладок: во время прогулки нижняя
  /// навигация только мешает, а открытый чужой маршрут — это отдельный экран.
  static const routeRecorder = '/route-recorder';
  static const routes = '/routes';

  /// Обсуждение поста — тоже отдельный экран: ветки требуют всей высоты.
  static const posts = '/posts';

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

      // Выключённую функцию нельзя открыть и по прямой ссылке: без ветки
      // роутера такой адрес иначе упирается в экран ошибки.
      if (!Features.chat && location.startsWith(Routes.chats)) {
        return Routes.feed;
      }

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
      GoRoute(
        path: Routes.routeRecorder,
        builder: (_, _) => const RouteRecorderScreen(),
      ),
      GoRoute(
        path: '${Routes.routes}/:routeId',
        builder: (_, state) =>
            RouteDetailScreen(routeId: state.pathParameters['routeId']!),
      ),
      GoRoute(
        path: '${Routes.posts}/:postId',
        builder: (_, state) => PostDetailScreen(
          postId: state.pathParameters['postId']!,
          post: state.extra as Post?,
        ),
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
                path: Routes.events,
                builder: (_, _) => const EventsScreen(),
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
          // Ветка чатов существует только при включённом флаге: в релизе
          // переписки в продукте нет, см. Features.chat.
          if (Features.chat)
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: Routes.chats,
                  builder: (_, _) => const ConversationsScreen(),
                  routes: [
                    GoRoute(
                      path: ':conversationId',
                      builder: (_, state) => ChatScreen(
                        conversationId: state.pathParameters['conversationId']!,
                        peerName: state.extra as String? ?? 'Чат',
                      ),
                    ),
                  ],
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
