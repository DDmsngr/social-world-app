import '../entities/post.dart';

abstract interface class FeedRepository {
  /// Лента города. [authorId] сужает её до публикаций одного человека —
  /// этим же запросом живёт вкладка профиля.
  Future<List<Post>> loadFeed({String? authorId, int limit = 50});

  Future<Post> createPost({
    required String body,
    PostKind kind = PostKind.text,
    List<String> mediaUrls = const [],
    String? placeTitle,
  });

  /// Возвращает пост с обновлённым счётчиком, чтобы экран не пересчитывал сам.
  Future<Post> toggleLike(Post post);

  Future<void> deletePost(String postId);
}
