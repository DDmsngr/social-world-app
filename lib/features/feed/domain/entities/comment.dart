/// Комментарий из ветки обсуждения.
///
/// [depth] приходит с сервера уже посчитанной: список плоский и лежит в
/// порядке обхода дерева, экрану остаётся отрисовать отступ.
class Comment {
  const Comment({
    required this.id,
    required this.postId,
    required this.authorId,
    required this.authorName,
    required this.createdAt,
    required this.depth,
    this.parentId,
    this.authorAvatarUrl,
    this.body,
    this.mediaUrls = const [],
    this.likeCount = 0,
    this.likedByMe = false,
    this.dislikeCount = 0,
    this.dislikedByMe = false,
    this.deleted = false,
  });

  final String id;
  final String postId;
  final String? parentId;
  final String authorId;
  final String authorName;
  final String? authorAvatarUrl;

  /// У удалённого комментария текста нет: сам узел остаётся в дереве, чтобы
  /// ответы на него не осиротели.
  final String? body;

  /// Задел под фото и гифки в комментариях: колонка и разбор готовы, кнопки
  /// прикрепления в интерфейсе пока нет.
  final List<String> mediaUrls;

  final DateTime createdAt;
  final int depth;
  final int likeCount;
  final bool likedByMe;
  final int dislikeCount;
  final bool dislikedByMe;
  final bool deleted;

  bool get hasMedia => mediaUrls.isNotEmpty;

  /// Голос человека: 1 — нравится, -1 — не нравится, 0 — без голоса.
  int get myVote => likedByMe ? 1 : (dislikedByMe ? -1 : 0);

  /// Комментарий после голоса [vote] (1, -1 или 0): счётчики пересчитываются
  /// сразу, не дожидаясь ответа сервера.
  Comment withVote(int vote) => copyWith(
    likedByMe: vote == 1,
    dislikedByMe: vote == -1,
    likeCount: likeCount - (likedByMe ? 1 : 0) + (vote == 1 ? 1 : 0),
    dislikeCount: dislikeCount - (dislikedByMe ? 1 : 0) + (vote == -1 ? 1 : 0),
  );

  Comment copyWith({
    int? likeCount,
    bool? likedByMe,
    int? dislikeCount,
    bool? dislikedByMe,
    bool? deleted,
    String? body,
  }) {
    return Comment(
      id: id,
      postId: postId,
      parentId: parentId,
      authorId: authorId,
      authorName: authorName,
      authorAvatarUrl: authorAvatarUrl,
      body: deleted ?? this.deleted ? null : (body ?? this.body),
      mediaUrls: deleted ?? this.deleted ? const [] : mediaUrls,
      createdAt: createdAt,
      depth: depth,
      likeCount: likeCount ?? this.likeCount,
      likedByMe: likedByMe ?? this.likedByMe,
      dislikeCount: dislikeCount ?? this.dislikeCount,
      dislikedByMe: dislikedByMe ?? this.dislikedByMe,
      deleted: deleted ?? this.deleted,
    );
  }
}
