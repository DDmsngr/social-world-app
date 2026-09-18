import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/env.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../moderation/presentation/providers/report_providers.dart';
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

class FeedController extends AsyncNotifier<List<Post>> {
  @override
  Future<List<Post>> build() async {
    ref.keepAlive();
    // Пересоздание после выхода (resetSessionScopedProviders) не должно
    // стрелять запросом без сессии — city_feed доступна только authenticated,
    // без охраны это была бы гарантированная ошибка ровно в момент логаута.
    if (ref.watch(currentUserProvider) == null) return const [];
    final posts = await ref.watch(feedRepositoryProvider).loadFeed();
    return _withoutHidden(posts);
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final posts = await ref.read(feedRepositoryProvider).loadFeed();
      return _withoutHidden(posts);
    });
  }

  /// Лайк применяется на месте: перезагружать ленту ради одного счётчика
  /// значит терять позицию скролла.
  Future<void> toggleLike(Post post) async {
    final updated = await ref.read(feedRepositoryProvider).toggleLike(post);
    state = AsyncValue.data([
      for (final item in state.value ?? const <Post>[])
        if (item.id == updated.id) updated else item,
    ]);
  }

  void prepend(Post post) {
    state = AsyncValue.data([post, ...?state.value]);
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
    final hidden = ref.read(reportRepositoryProvider).hiddenTargetIds;
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
final myPostsProvider = FutureProvider<List<Post>>((ref) async {
  final userId = ref.watch(currentUserProvider)?.id;
  if (userId == null) return const [];
  return ref.watch(feedRepositoryProvider).loadFeed(authorId: userId);
});
