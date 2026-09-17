import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/features/feed/domain/comment_thread.dart';
import 'package:social_world/features/feed/domain/entities/comment.dart';

Comment _comment(String id, {String? parentId, required int depth}) => Comment(
  id: id,
  postId: 'post-1',
  parentId: parentId,
  authorId: 'someone',
  authorName: 'Кто-то',
  body: id,
  createdAt: DateTime(2026, 9, 17),
  depth: depth,
);

void main() {
  group('insertIntoThread', () {
    test('корневой комментарий встаёт первым', () {
      final thread = [_comment('a', depth: 0)];

      final result = insertIntoThread(thread, _comment('b', depth: 0));

      expect(result.map((c) => c.id), ['b', 'a']);
    });

    // Главная ловушка порядка: ответ должен встать после всего поддерева
    // родителя, иначе он окажется выше более ранних ответов и разговор
    // придётся читать снизу вверх.
    test('ответ встаёт после всего поддерева родителя', () {
      final thread = [
        _comment('root', depth: 0),
        _comment('reply-1', parentId: 'root', depth: 1),
        _comment('reply-1-1', parentId: 'reply-1', depth: 2),
        _comment('other-root', depth: 0),
      ];

      final result = insertIntoThread(
        thread,
        _comment('reply-2', parentId: 'root', depth: 1),
      );

      expect(result.map((c) => c.id), [
        'root',
        'reply-1',
        'reply-1-1',
        'reply-2',
        'other-root',
      ]);
    });

    test('ответ на неизвестный узел не теряется', () {
      final thread = [_comment('root', depth: 0)];

      final result = insertIntoThread(
        thread,
        _comment('orphan', parentId: 'unknown', depth: 1),
      );

      expect(result.map((c) => c.id), ['root', 'orphan']);
    });
  });

  group('visibleThread', () {
    final thread = [
      _comment('root', depth: 0),
      _comment('reply', parentId: 'root', depth: 1),
      _comment('deep', parentId: 'reply', depth: 2),
      _comment('other', depth: 0),
    ];

    test('без свёрнутых веток видно всё', () {
      final rows = visibleThread(thread, {});

      expect(rows.map((row) => row.comment.id), [
        'root',
        'reply',
        'deep',
        'other',
      ]);
      expect(rows.every((row) => row.hiddenReplies == 0), isTrue);
    });

    test('свёрнутая ветка прячет всё поддерево, а не только детей', () {
      final rows = visibleThread(thread, {'root'});

      expect(rows.map((row) => row.comment.id), ['root', 'other']);
      expect(rows.first.hiddenReplies, 2);
      expect(rows.first.collapsed, isTrue);
    });

    test('свёрнутая середина ветки не трогает соседей', () {
      final rows = visibleThread(thread, {'reply'});

      expect(rows.map((row) => row.comment.id), ['root', 'reply', 'other']);
      expect(rows[1].hiddenReplies, 1);
    });
  });
}
