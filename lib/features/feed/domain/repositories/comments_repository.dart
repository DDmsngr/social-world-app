import '../entities/comment.dart';

/// Сколько картинок можно приложить к одному комментарию.
const maxCommentMedia = 4;

abstract interface class CommentsRepository {
  /// Ветка обсуждения поста: плоский список в порядке дерева, глубина в
  /// каждом элементе.
  Future<List<Comment>> loadThread(String postId);

  /// [parent] задаёт ответ в ветке. Передаётся объектом, а не id: от него же
  /// берётся глубина нового узла.
  ///
  /// [mediaPaths] — файлы с телефона (фото или гифки, до [maxCommentMedia]):
  /// репозиторий сам их загружает. Комментарий может быть и без текста, если
  /// есть хотя бы одна картинка.
  Future<Comment> addComment({
    required String postId,
    required String body,
    Comment? parent,
    List<String> mediaPaths = const [],
  });

  /// Голос за комментарий: 1 — нравится, -1 — не нравится, 0 — снять голос.
  /// Один голос на человека: новый заменяет прежний.
  Future<void> setVote(Comment comment, int vote);

  /// Удаление мягкое: узел остаётся в дереве, чтобы ответы не пропали вместе
  /// с ним.
  Future<Comment> deleteComment(Comment comment);
}
