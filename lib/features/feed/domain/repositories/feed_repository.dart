import '../entities/post.dart';
import '../entities/publish_settings.dart';

abstract interface class FeedRepository {
  /// Лента города. [authorId] сужает её до публикаций одного человека —
  /// этим же запросом живёт вкладка профиля. Сервер сам скрывает то, что
  /// автор не разрешил показывать вошедшему (подписчикам, только себе).
  Future<List<Post>> loadFeed({String? authorId, int limit = 50});

  /// Один пост по id: для ссылок, уведомлений и «Сохранённого», когда поста
  /// нет в уже загруженной ленте. `null` — не существует или недоступен.
  Future<Post?> loadPost(String postId);

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
    PostType postType = PostType.moment,
    String? title,
    BodyFormat bodyFormat = BodyFormat.plain,
    PublishSettings settings = PublishSettings.defaults,
    List<String> mediaPaths = const [],
    String? placeId,
    String? placeTitle,
    double? placeLatitude,
    double? placeLongitude,
    String? routeId,
  });

  /// Правка собственного поста. [keepMediaUrls] — вложения, которые остаются,
  /// [newMediaPaths] — новые файлы с устройства. Чужой пост — [PermissionDeniedException].
  Future<Post> updatePost(
    Post post, {
    required String body,
    String? title,
    BodyFormat? bodyFormat,
    required PublishSettings settings,
    required List<String> keepMediaUrls,
    List<String> newMediaPaths = const [],
    String? placeId,
    String? placeTitle,
    double? placeLatitude,
    double? placeLongitude,
  });

  /// Кладёт картинку в хранилище и возвращает ссылку — для вставки в текст
  /// статьи, где файл нужен ещё до публикации.
  Future<String> uploadInlineImage(String localPath);

  /// Возвращает пост с обновлённым счётчиком, чтобы экран не пересчитывал сам.
  Future<Post> toggleLike(Post post);

  Future<void> deletePost(String postId);
}
