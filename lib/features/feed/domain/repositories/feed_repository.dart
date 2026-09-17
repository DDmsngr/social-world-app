import '../entities/post.dart';

abstract interface class FeedRepository {
  /// Лента города. [authorId] сужает её до публикаций одного человека —
  /// этим же запросом живёт вкладка профиля.
  Future<List<Post>> loadFeed({String? authorId, int limit = 50});

  /// [routeId] превращает пост в карточку маршрута: сам маршрут к этому моменту
  /// уже сохранён, лента только делает его видимым.
  Future<Post> createPost({
    required String body,
    PostKind kind = PostKind.text,
    List<String> mediaUrls = const [],
    String? placeTitle,
    String? routeId,
  });

  /// Возвращает пост с обновлённым счётчиком, чтобы экран не пересчитывал сам.
  Future<Post> toggleLike(Post post);

  Future<void> deletePost(String postId);
}
