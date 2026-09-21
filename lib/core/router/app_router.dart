import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../config/feature_flags.dart';
import '../session/session_reset.dart';

import '../../features/auth/domain/entities/app_user.dart';
import '../../features/chat/presentation/chat_screen.dart';
import '../../features/chat/presentation/chats_soon_screen.dart';
import '../../features/chat/presentation/conversations_screen.dart';
import '../../features/auth/presentation/providers/auth_providers.dart';
import '../../features/auth/presentation/screens/onboarding_screen.dart';
import '../../features/auth/presentation/screens/sign_in_screen.dart';
import '../../features/create/presentation/create_screen.dart';
import '../../features/discover/presentation/discover_screen.dart';
import '../../features/discover/presentation/place_screen.dart';
import '../../features/events/domain/entities/event.dart';
import '../../features/events/presentation/event_detail_screen.dart';
import '../../features/events/presentation/events_screen.dart';
import '../../features/feed/domain/entities/post.dart';
import '../../features/feed/presentation/feed_screen.dart';
import '../../features/feed/presentation/post_detail_screen.dart';
import '../../features/feed/presentation/post_edit_screen.dart';
import '../../features/notifications/notifications_screen.dart';
import '../../features/profile/presentation/blocked_users_screen.dart';
import '../../features/profile/presentation/edit_profile_screen.dart';
import '../../features/profile/presentation/user_profile_screen.dart';
import '../../features/saved/saved_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/profile/presentation/settings_screen.dart';
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
  static const home = discover;

  /// Список событий открывается с карты («Пульс города»), вкладки у него нет.
  static const events = '/events';
  static const create = '/create';
  static const chats = '/chats';
  static const profile = '/profile';
  static const settings = '/profile/settings';
  static const editProfile = '/profile/edit';
  static const blocked = '/profile/blocked';

  /// Профиль любого человека: ${Routes.user}/id. Свой открывается тем же
  /// экраном и показывает действия владельца.
  static const user = '/users';
  static const saved = '/saved';
  static const notifications = '/notifications';
  static const places = '/places';

  /// Запись и просмотр маршрутов живут вне вкладок: во время прогулки нижняя
  /// навигация только мешает, а открытый чужой маршрут — это отдельный экран.
  static const routeRecorder = '/route-recorder';
  static const routes = '/routes';

  /// Обсуждение поста — тоже отдельный экран: ветки требуют всей высоты.
  static const posts = '/posts';

  /// Карточка одного события — вне вкладок по той же причине, что и посты.
  static const eventDetail = '/event';

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
  String? lastUid;
  ref.listen(authStateProvider, (_, next) {
    auth.value = next;

    // Сравниваем именно подтверждённый UID, а не сам факт нового события:
    // обновление токена или профиля у того же человека (completeProfile,
    // радиус гео) не должно сбрасывать ленту/чаты — только смена того, кто
    // вошёл, включая выход.
    final nextUid = next.value?.id;
    if (nextUid != lastUid) {
      lastUid = nextUid;
      resetSessionScopedProviders(ref);
    }
  }, fireImmediately: true);
  ref.onDispose(auth.dispose);

  // Полноэкранный hero-баннер (SplashScreen) должен успеть нарисовать хотя бы
  // один кадр: при мгновенно восстановленной сессии (кэш VK/Яндекс-токена)
  // redirect иначе срабатывает раньше первого кадра, и виден только маленький
  // нативный значок Android 12+ SplashScreen API. Защёлка на Timer, а не на
  // DateTime.now() — под flutter_test часы виртуальные и не двигаются, а вот
  // сам Timer через pumpAndSettle честно "срабатывает".
  var splashElapsed = false;
  final splashTimer = Timer(const Duration(milliseconds: 1700), () {
    splashElapsed = true;
    auth.value = auth.value;
  });
  ref.onDispose(splashTimer.cancel);

  return GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: auth,
    // Неизвестный адрес (устаревшая ссылка, битый диплинк) — на карту, а не на
    // экран с ошибкой роутера.
    onException: (_, state, router) => router.go(Routes.home),
    redirect: (context, state) {
      final location = state.matchedLocation;

      // Пока переписка выключена, вкладка «Чаты» показывает заглушку, а
      // прямая ссылка на конкретный чат ведёт туда же, а не в экран ошибки.
      if (!Features.chat && location.startsWith('${Routes.chats}/')) {
        return Routes.chats;
      }

      if (auth.isResolving || !splashElapsed) {
        return location == Routes.splash ? null : Routes.splash;
      }

      final user = auth.user;
      if (user == null) {
        return location == Routes.signIn ? null : Routes.signIn;
      }
      if (!user.hasProfile) {
        return location == Routes.onboarding ? null : Routes.onboarding;
      }

      // Главный экран — карта города: с неё начинается всё остальное.
      return Routes.authFlow.contains(location) ? Routes.home : null;
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
      GoRoute(
        path: '${Routes.eventDetail}/:eventId',
        builder: (_, state) => EventDetailScreen(
          eventId: state.pathParameters['eventId']!,
          event: state.extra as Event?,
        ),
      ),
      GoRoute(
        path: '${Routes.posts}/:postId/edit',
        builder: (_, state) => PostEditScreen(
          postId: state.pathParameters['postId']!,
          post: state.extra as Post?,
        ),
      ),
      GoRoute(
        path: '${Routes.user}/:userId',
        builder: (_, state) =>
            UserProfileScreen(userId: state.pathParameters['userId']!),
      ),
      GoRoute(
        path: '${Routes.places}/:placeId',
        builder: (_, state) =>
            PlaceScreen(placeId: state.pathParameters['placeId']!),
      ),
      GoRoute(
        path: Routes.editProfile,
        builder: (_, _) => const EditProfileScreen(),
      ),
      GoRoute(
        path: Routes.blocked,
        builder: (_, _) => const BlockedUsersScreen(),
      ),
      GoRoute(path: Routes.saved, builder: (_, _) => const SavedScreen()),
      GoRoute(
        path: Routes.notifications,
        builder: (_, _) => const NotificationsScreen(),
      ),
      GoRoute(
        path: Routes.settings,
        builder: (_, _) => const SettingsScreen(),
      ),
      GoRoute(
        path: Routes.events,
        builder: (_, _) => const EventsScreen(),
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
          // Вкладка есть всегда, но сама переписка — только при включённом
          // флаге (см. Features.chat): до этого там заглушка без запросов к
          // серверу.
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.chats,
                builder: (_, _) => Features.chat
                    ? const ConversationsScreen()
                    : const ChatsSoonScreen(),
                routes: [
                  if (Features.chat)
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
