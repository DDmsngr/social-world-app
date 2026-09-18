import '../entities/post.dart';

abstract interface class FeedRepository {
  /// Лента города. [authorId] сужает её до публикаций одного человека —
  /// этим же запросом живёт вкладка профиля.
  Future<List<Post>> loadFeed({String? authorId, int limit = 50});

  /// [routeId] превращает пост в карточку маршрута: сам маршрут к этому моменту
  /// уже сохранён, лента только делает его видимым.
  ///
  /// [mediaPaths] — файлы на устройстве; в хранилище их кладёт репозиторий,
  /// чтобы экран не знал ни про бакеты, ни про то, что в моках загрузки нет.
  /// [placeId] и [placeTitle] приходят из уже выбранного в UI места одной
  /// парой: резолвить id по названию в репозитории нельзя — при совпадающих
  /// названиях (реальный случай при краудсорсинге мест) `maybeSingle()`
  /// падает на нескольких найденных строках.
  Future<Post> createPost({
    required String body,
    PostKind kind = PostKind.text,
    List<String> mediaPaths = const [],
    String? placeId,
    String? placeTitle,
    String? routeId,
  });

  /// Возвращает пост с обновлённым счётчиком, чтобы экран не пересчитывал сам.
  Future<Post> toggleLike(Post post);

  Future<void> deletePost(String postId);
}
