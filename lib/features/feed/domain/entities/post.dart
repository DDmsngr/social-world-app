enum PostKind { text, photo, video, short }

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
    this.likeCount = 0,
    this.likedByMe = false,
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

  final DateTime createdAt;
  final int likeCount;
  final bool likedByMe;

  bool get hasMedia => mediaUrls.isNotEmpty;

  Post copyWith({int? likeCount, bool? likedByMe}) => Post(
    id: id,
    authorId: authorId,
    authorName: authorName,
    authorAvatarUrl: authorAvatarUrl,
    kind: kind,
    body: body,
    mediaUrls: mediaUrls,
    placeTitle: placeTitle,
    createdAt: createdAt,
    likeCount: likeCount ?? this.likeCount,
    likedByMe: likedByMe ?? this.likedByMe,
  );
}
