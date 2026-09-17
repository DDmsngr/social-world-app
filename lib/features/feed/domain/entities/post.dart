import '../../../../core/media/media_kind.dart';

enum PostKind { text, photo, video, short }

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
    this.mediaUrls = const [],
    this.placeTitle,
    this.routeId,
    this.likeCount = 0,
    this.likedByMe = false,
    this.commentCount = 0,
  });

  final String id;
  final String authorId;
  final String authorName;
  final String? authorAvatarUrl;
  final PostKind kind;
  final String? body;
  final List<String> mediaUrls;

  /// Название места, а не координаты: в ленте точка на карте не нужна,
  /// а лишние гео-данные на экране — лишний риск.
  final String? placeTitle;

  /// Заполнен, если пост — обёртка над маршрутом. Тип поста для этого не
  /// заводили: значение в post_kind нельзя добавить и сразу же использовать
  /// в одной миграции, а ссылка на маршрут опознаёт его однозначно.
  final String? routeId;

  final DateTime createdAt;
  final int likeCount;
  final bool likedByMe;
  final int commentCount;

  bool get hasMedia => mediaUrls.isNotEmpty;
  bool get isRoute => routeId != null;

  Post copyWith({int? likeCount, bool? likedByMe, int? commentCount}) => Post(
    id: id,
    authorId: authorId,
    authorName: authorName,
    authorAvatarUrl: authorAvatarUrl,
    kind: kind,
    body: body,
    mediaUrls: mediaUrls,
    placeTitle: placeTitle,
    routeId: routeId,
    createdAt: createdAt,
    likeCount: likeCount ?? this.likeCount,
    likedByMe: likedByMe ?? this.likedByMe,
    commentCount: commentCount ?? this.commentCount,
  );
}
