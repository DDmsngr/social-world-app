import '../entities/comment.dart';

abstract interface class CommentsRepository {
  /// Ветка обсуждения поста: плоский список в порядке дерева, глубина в
  /// каждом элементе.
  Future<List<Comment>> loadThread(String postId);

  /// [parent] задаёт ответ в ветке. Передаётся объектом, а не id: от него же
  /// берётся глубина нового узла.
  Future<Comment> addComment({
    required String postId,
    required String body,
    Comment? parent,
  });

  /// Голос за комментарий: 1 — нравится, -1 — не нравится, 0 — снять голос.
  /// Один голос на человека: новый заменяет прежний.
  Future<void> setVote(Comment comment, int vote);

  /// Удаление мягкое: узел остаётся в дереве, чтобы ответы не пропали вместе
  /// с ним.
  Future<Comment> deleteComment(Comment comment);
}
