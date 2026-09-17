import '../domain/comment_thread.dart';
import '../domain/entities/comment.dart';
import '../domain/repositories/comments_repository.dart';

/// Комментарии на моках, пока Supabase не поднят. Порядок в списке держится
/// тот же, что у серверного дерева, — иначе веб-прогон показывал бы ветки
/// иначе, чем телефон.
class LocalCommentsRepository implements CommentsRepository {
  LocalCommentsRepository({
    required this.currentUserId,
    required this.currentUserName,
  });

  final String Function() currentUserId;
  final String Function() currentUserName;

  late final Map<String, List<Comment>> _threads = {'seed-1': _seed};
  var _nextId = 0;

  @override
  Future<List<Comment>> loadThread(String postId) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    return List.unmodifiable(_threads[postId] ?? const <Comment>[]);
  }

  @override
  Future<Comment> addComment({
    required String postId,
    required String body,
    Comment? parent,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final comment = Comment(
      id: 'local-comment-${_nextId++}',
      postId: postId,
      parentId: parent?.id,
      authorId: currentUserId(),
      authorName: currentUserName(),
      body: body.trim(),
      createdAt: DateTime.now(),
      depth: parent == null ? 0 : parent.depth + 1,
    );

    _threads[postId] = insertIntoThread(_threads[postId] ?? const [], comment);
    return comment;
  }

  @override
  Future<Comment> toggleLike(Comment comment) async {
    final liked = !comment.likedByMe;
    final updated = comment.copyWith(
      likedByMe: liked,
      likeCount: comment.likeCount + (liked ? 1 : -1),
    );
    _replace(updated);
    return updated;
  }

  @override
  Future<Comment> deleteComment(Comment comment) async {
    final updated = comment.copyWith(deleted: true);
    _replace(updated);
    return updated;
  }

  void _replace(Comment comment) {
    final thread = _threads[comment.postId];
    if (thread == null) return;
    _threads[comment.postId] = [
      for (final item in thread)
        if (item.id == comment.id) comment else item,
    ];
  }

  static final _seed = <Comment>[
    Comment(
      id: 'seed-comment-1',
      postId: 'seed-1',
      authorId: 'person-3',
      authorName: 'Саша',
      body: 'Вода реально тёплая? Собираюсь завтра с утра.',
      createdAt: DateTime.now().subtract(const Duration(minutes: 18)),
      depth: 0,
      likeCount: 3,
    ),
    Comment(
      id: 'seed-comment-2',
      postId: 'seed-1',
      parentId: 'seed-comment-1',
      authorId: 'person-1',
      authorName: 'Алина',
      body: 'Двадцать два, для сентября отлично.',
      createdAt: DateTime.now().subtract(const Duration(minutes: 12)),
      depth: 1,
      likeCount: 2,
    ),
    Comment(
      id: 'seed-comment-3',
      postId: 'seed-1',
      parentId: 'seed-comment-2',
      authorId: 'person-3',
      authorName: 'Саша',
      body: 'Тогда буду.',
      createdAt: DateTime.now().subtract(const Duration(minutes: 9)),
      depth: 2,
    ),
    Comment(
      id: 'seed-comment-4',
      postId: 'seed-1',
      authorId: 'person-6',
      authorName: 'Ника',
      body: 'Там же сейчас стройка на входе, как прошли?',
      createdAt: DateTime.now().subtract(const Duration(minutes: 40)),
      depth: 0,
    ),
  ];
}
