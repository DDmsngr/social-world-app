import 'entities/comment.dart';

typedef ThreadRow = ({Comment comment, int hiddenReplies, bool collapsed});

/// Оставляет в плоском списке только то, что видно при свёрнутых ветках
/// [collapsed], и считает, сколько ответов спрятано под каждой из них.
///
/// Свёрнутый узел прячет всё своё поддерево, а не только прямых детей:
/// схлопнуть ветку и увидеть её внуков было бы странно.
List<ThreadRow> visibleThread(List<Comment> thread, Set<String> collapsed) {
  final rows = <ThreadRow>[];
  var hiddenBelowDepth = -1;

  for (var index = 0; index < thread.length; index++) {
    final comment = thread[index];
    if (hiddenBelowDepth >= 0 && comment.depth > hiddenBelowDepth) continue;
    hiddenBelowDepth = -1;

    final isCollapsed = collapsed.contains(comment.id);
    var hiddenReplies = 0;
    if (isCollapsed) {
      var scan = index + 1;
      while (scan < thread.length && thread[scan].depth > comment.depth) {
        hiddenReplies++;
        scan++;
      }
      hiddenBelowDepth = comment.depth;
    }

    rows.add((
      comment: comment,
      hiddenReplies: hiddenReplies,
      collapsed: isCollapsed,
    ));
  }

  return rows;
}

/// Вставляет новый комментарий в плоский список, упорядоченный обходом дерева.
///
/// Порядок повторяет `post_comments_tree` из миграции 0009: корневые ветки —
/// свежие сверху, ответы внутри ветки — снизу, в порядке разговора. Поэтому
/// ответ встаёт не сразу за родителем, а после всего его поддерева: иначе он
/// оказался бы выше более ранних ответов и разговор пришлось бы читать задом
/// наперёд до следующей перезагрузки.
List<Comment> insertIntoThread(List<Comment> thread, Comment comment) {
  if (comment.parentId == null) return [comment, ...thread];

  final parentIndex = thread.indexWhere((item) => item.id == comment.parentId);
  if (parentIndex == -1) return [...thread, comment];

  final parentDepth = thread[parentIndex].depth;
  var insertAt = parentIndex + 1;
  while (insertAt < thread.length && thread[insertAt].depth > parentDepth) {
    insertAt++;
  }

  return [
    ...thread.take(insertAt),
    comment,
    ...thread.skip(insertAt),
  ];
}
