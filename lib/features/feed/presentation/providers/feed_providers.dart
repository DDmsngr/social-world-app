import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/env.dart';
import '../../../../core/debug/app_log.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../discover/presentation/providers/city_provider.dart';
import '../../../moderation/presentation/providers/report_providers.dart';
import '../../../profile/presentation/providers/profile_providers.dart';
import '../../data/local_feed_repository.dart';
import '../../data/supabase_feed_repository.dart';
import '../../domain/entities/post.dart';
import '../../domain/repositories/feed_repository.dart';

final feedRepositoryProvider = Provider<FeedRepository>((ref) {
  // keepAlive: у заглушки лента лежит в памяти, пересоздание стёрло бы
  // всё, что пользователь успел опубликовать.
  ref.keepAlive();
  if (!Env.isConfigured) {
    return LocalFeedRepository(
      currentUserId: () => ref.read(currentUserProvider)?.id ?? 'local-user',
      currentUserName: () =>
          ref.read(currentUserProvider)?.displayName ?? 'Вы',
    );
  }
  return SupabaseFeedRepository(Supabase.instance.client);
});

/// Охват ленты: «Для вас» (по интересам), страна или город (п. 47 ТЗ). По
/// умолчанию — «Для вас»; выбор живёт до перезапуска.
enum FeedScope {
  forYou('Для вас'),
  country('Страна'),
  city('Город');

  const FeedScope(this.label);

  final String label;
}

class FeedScopeController extends Notifier<FeedScope> {
  @override
  FeedScope build() {
    ref.keepAlive();
    return FeedScope.forYou;
  }

  void set(FeedScope scope) => state = scope;
}

final feedScopeProvider = NotifierProvider<FeedScopeController, FeedScope>(
  FeedScopeController.new,
);

/// Город для запроса ленты: выбранный на Pulse в режиме «Город», иначе null.
final feedCityFilterProvider = Provider<String?>((ref) {
  if (ref.watch(feedScopeProvider) != FeedScope.city) return null;
  return ref.watch(cityProvider).name;
});

/// Популярные хэштеги для полосы над лентой.
final trendingHashtagsProvider =
    FutureProvider.autoDispose<List<({String tag, int posts})>>((ref) async {
      try {
        return await ref.watch(feedRepositoryProvider).trendingHashtags();
      } catch (error) {
        AppLog.add('Популярные теги не загрузились: $error');
        return const [];
      }
    });

/// Лента одного хэштега.
final hashtagFeedProvider = FutureProvider.autoDispose.family<List<Post>, String>(
  (ref, tag) => ref.watch(feedRepositoryProvider).loadFeed(tag: tag),
);

class FeedController extends AsyncNotifier<List<Post>> {
  @override
  Future<List<Post>> build() async {
    ref.keepAlive();
    // Пересоздание после выхода (resetSessionScopedProviders) не должно
    // стрелять запросом без сессии — city_feed доступна только authenticated,
    // без охраны это была бы гарантированная ошибка ровно в момент логаута.
    if (ref.watch(currentUserProvider) == null) return const [];
    final posts = await ref.watch(feedRepositoryProvider).loadFeed(
      city: ref.watch(feedCityFilterProvider),
      forYou: ref.watch(feedScopeProvider) == FeedScope.forYou,
    );
    return _withoutHidden(posts);
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final posts = await ref.read(feedRepositoryProvider).loadFeed(
        city: ref.read(feedCityFilterProvider),
        forYou: ref.read(feedScopeProvider) == FeedScope.forYou,
      );
      return _withoutHidden(posts);
    });
    ref.invalidate(trendingHashtagsProvider);
  }

  /// Лайк применяется на месте: перезагружать ленту ради одного счётчика
  /// значит терять позицию скролла.
  final _likesInFlight = <String>{};

  /// Возвращает false, если лайк не сохранился — экран показывает сообщение.
  /// Раньше сеть отваливалась молча: сердечко не менялось, и человек тыкал
  /// в него снова, не понимая, почему ничего не происходит.
  Future<bool> toggleLike(Post post) async {
    // Один запрос на пост за раз: два быстрых тапа иначе гоняют лайк и его
    // снятие наперегонки, и в базе остаётся случайный из двух.
    if (!_likesInFlight.add(post.id)) return true;

    // Сердечко отзывается сразу, не дожидаясь ответа сервера.
    _replace(
      post.copyWith(
        likedByMe: !post.likedByMe,
        likeCount: post.likeCount + (post.likedByMe ? -1 : 1),
      ),
    );

    try {
      _replace(await ref.read(feedRepositoryProvider).toggleLike(post));
      return true;
    } catch (error) {
      AppLog.add('Лайк не сохранился: $error');
      _replace(post);
      return false;
    } finally {
      _likesInFlight.remove(post.id);
    }
  }

  void _replace(Post updated) {
    state = AsyncValue.data([
      for (final item in state.value ?? const <Post>[])
        if (item.id == updated.id) updated else item,
    ]);
  }

  void prepend(Post post) {
    state = AsyncValue.data([post, ...?state.value]);
  }

  /// Пост после правки: лента показывает новую версию без перезагрузки.
  void replacePost(Post post) => _replace(post);

  void remove(String postId) {
    state = AsyncValue.data([
      for (final item in state.value ?? const <Post>[])
        if (item.id != postId) item,
    ]);
  }

  /// Счётчик на карточке должен совпадать с тем, что человек только что
  /// написал в ветке: иначе, вернувшись в ленту, он видит, что комментария
  /// будто и не было.
  void bumpCommentCount(String postId, int delta) {
    state = AsyncValue.data([
      for (final item in state.value ?? const <Post>[])
        if (item.id == postId)
          item.copyWith(commentCount: item.commentCount + delta)
        else
          item,
    ]);
  }

  /// После жалобы контент исчезает сразу, не дожидаясь разбора.
  void hide(String targetId) {
    state = AsyncValue.data([
      for (final item in state.value ?? const <Post>[])
        if (item.id != targetId && item.authorId != targetId) item,
    ]);
  }

  List<Post> _withoutHidden(List<Post> posts) {
    final hidden = {
      ...ref.read(reportRepositoryProvider).hiddenTargetIds,
      ...?ref.read(blocksProvider).value?.keys,
    };
    if (hidden.isEmpty) return posts;
    return posts
        .where(
          (post) =>
              !hidden.contains(post.id) && !hidden.contains(post.authorId),
        )
        .toList(growable: false);
  }
}

final feedProvider = AsyncNotifierProvider<FeedController, List<Post>>(
  FeedController.new,
);

/// Публикации текущего пользователя — этим живёт вкладка профиля.
/// Один пост по id — для оригинала внутри репоста.
final postByIdProvider = FutureProvider.autoDispose.family<Post?, String>(
  (ref, id) => ref.watch(feedRepositoryProvider).loadPost(id),
);

final myPostsProvider = FutureProvider<List<Post>>((ref) async {
  final userId = ref.watch(currentUserProvider)?.id;
  if (userId == null) return const [];
  return ref.watch(feedRepositoryProvider).loadFeed(authorId: userId);
});
