import '../../../../core/media/media_kind.dart';

enum PostKind { text, photo, video, short }

/// Формат публикации. Моменты остаются короткими и быстрыми, статья — длинный
/// текст с заголовком. Значение хранится строкой (а не enum'ом Postgres), чтобы
/// добавить новый формат без `ALTER TYPE`.
enum PostType {
  moment,
  article;

  static PostType parse(dynamic raw) => PostType.values.firstWhere(
    (type) => type.name == raw,
    orElse: () => PostType.moment,
  );
}

/// Как хранится текст. Markdown разбирается только при показе, в базе лежит
/// исходник — его можно открыть на редактирование в том же виде.
enum BodyFormat {
  plain,
  markdown;

  static BodyFormat parse(dynamic raw) => BodyFormat.values.firstWhere(
    (format) => format.name == raw,
    orElse: () => BodyFormat.plain,
  );
}

/// Кому виден пост. Проверяется на сервере (city_feed и политика select), а
/// не только скрывается в интерфейсе.
enum PostVisibility {
  everyone('Всем'),
  followers('Подписчикам'),
  onlyMe('Только мне');

  const PostVisibility(this.label);

  final String label;

  String get wire => switch (this) {
    PostVisibility.everyone => 'public',
    PostVisibility.followers => 'followers',
    PostVisibility.onlyMe => 'private',
  };

  static PostVisibility parse(dynamic raw) => switch (raw) {
    'followers' => PostVisibility.followers,
    'private' => PostVisibility.onlyMe,
    _ => PostVisibility.everyone,
  };
}

/// Тип поста определяется вложениями, а не формой: человек выбирает «пост»,
/// а фото это или видео — видно по тому, что он приложил.
PostKind postKindFor(PostKind fallback, List<String> media) {
  if (media.isEmpty) return fallback;
  return media.any(isVideoUrl) ? PostKind.video : PostKind.photo;
}

class Post {
  const Post({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.kind,
    required this.createdAt,
    this.authorAvatarUrl,
    this.body,
    this.title,
    this.postType = PostType.moment,
    this.bodyFormat = BodyFormat.plain,
    this.visibility = PostVisibility.everyone,
    this.showGeo = true,
    this.mediaUrls = const [],
    this.placeId,
    this.placeTitle,
    this.placeLatitude,
    this.placeLongitude,
    this.routeId,
    this.editedAt,
    this.likeCount = 0,
    this.likedByMe = false,
    this.commentCount = 0,
  });

  final String id;
  final String authorId;
  final String authorName;
  final String? authorAvatarUrl;
  final PostKind kind;
  final PostType postType;
  final String? title;
  final String? body;
  final BodyFormat bodyFormat;
  final PostVisibility visibility;

  /// Показывать ли место публикации другим. Автору место видно всегда.
  final bool showGeo;
  final List<String> mediaUrls;

  final String? placeId;

  /// Название места, а не координаты: в ленте точка на карте не нужна,
  /// а лишние гео-данные на экране — лишний риск.
  final String? placeTitle;

  /// Координаты места нужны только карте (моменты в слое активности) и
  /// приходят с сервера лишь тогда, когда автор разрешил показывать место.
  final double? placeLatitude;
  final double? placeLongitude;

  /// Заполнен, если пост — обёртка над маршрутом. Тип поста для этого не
  /// заводили: значение в post_kind нельзя добавить и сразу же использовать
  /// в одной миграции, а ссылка на маршрут опознаёт его однозначно.
  final String? routeId;

  final DateTime createdAt;
  final DateTime? editedAt;
  final int likeCount;
  final bool likedByMe;
  final int commentCount;

  bool get hasMedia => mediaUrls.isNotEmpty;
  bool get isRoute => routeId != null;
  bool get isArticle => postType == PostType.article;
  bool get hasPlaceGeo => placeLatitude != null && placeLongitude != null;

  /// Фото для ленты «историй»: только настоящие изображения, без видео.
  List<String> get photoUrls =>
      mediaUrls.where((url) => !isVideoUrl(url)).toList(growable: false);

  Post copyWith({
    int? likeCount,
    bool? likedByMe,
    int? commentCount,
    String? authorName,
    String? authorAvatarUrl,
  }) => Post(
    id: id,
    authorId: authorId,
    authorName: authorName ?? this.authorName,
    authorAvatarUrl: authorAvatarUrl ?? this.authorAvatarUrl,
    kind: kind,
    postType: postType,
    title: title,
    body: body,
    bodyFormat: bodyFormat,
    visibility: visibility,
    showGeo: showGeo,
    mediaUrls: mediaUrls,
    placeId: placeId,
    placeTitle: placeTitle,
    placeLatitude: placeLatitude,
    placeLongitude: placeLongitude,
    routeId: routeId,
    createdAt: createdAt,
    editedAt: editedAt,
    likeCount: likeCount ?? this.likeCount,
    likedByMe: likedByMe ?? this.likedByMe,
    commentCount: commentCount ?? this.commentCount,
  );
}
