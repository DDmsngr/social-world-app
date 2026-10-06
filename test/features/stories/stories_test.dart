import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/features/stories/stories.dart';

Story story(
  String id,
  String author, {
  int minute = 0,
  bool viewed = false,
  StoryKind kind = StoryKind.text,
}) => Story(
  id: id,
  authorId: author,
  authorName: author,
  kind: kind,
  body: 'текст',
  createdAt: DateTime(2026, 10, 6, 12, minute),
  viewed: viewed,
);

void main() {
  test('свои первыми, затем непросмотренные подписки, чужие и просмотренные', () {
    final groups = groupStories(
      [
        story('1', 'seen', minute: 5, viewed: true),
        story('2', 'stranger', minute: 4),
        story('3', 'friend', minute: 1),
        story('4', 'me', minute: 0),
      ],
      me: 'me',
      followed: {'friend', 'seen'},
    );
    expect([for (final g in groups) g.authorId], ['me', 'friend', 'stranger', 'seen']);
    expect(groups.first.isMine, isTrue);
  });

  test('внутри ранга свежие впереди, истории автора остаются по порядку', () {
    final groups = groupStories(
      [
        story('1', 'a', minute: 1),
        story('2', 'b', minute: 9),
        story('3', 'a', minute: 2),
      ],
      me: 'x',
    );
    expect([for (final g in groups) g.authorId], ['b', 'a']);
    expect([for (final s in groups.last.stories) s.id], ['1', '3']);
  });

  test('показ начинается с первой непросмотренной', () {
    final group = groupStories(
      [
        story('1', 'a', minute: 1, viewed: true),
        story('2', 'a', minute: 2, viewed: true),
        story('3', 'a', minute: 3),
      ],
      me: 'x',
    ).single;
    expect(group.startIndex, 2);
    expect(group.cover.id, '3');
    expect(group.allViewed, isFalse);
  });

  test('если всё просмотрено — с начала', () {
    final group = groupStories(
      [story('1', 'a', viewed: true), story('2', 'a', minute: 1, viewed: true)],
      me: 'x',
    ).single;
    expect(group.startIndex, 0);
    expect(group.allViewed, isTrue);
  });

  test('строка с сервера читается, время показа зажато в 3–30 с', () {
    final s = Story.fromRow({
      'id': 'i',
      'author_id': 'u',
      'author_name': 'Аня',
      'kind': 'photo',
      'media_url': 'https://x/y.jpg',
      'duration_sec': 99,
      'created_at': '2026-10-06T09:00:00Z',
      'viewed': true,
      'view_count': 4,
    });
    expect(s.kind, StoryKind.photo);
    expect(s.durationSec, maxVideoSeconds);
    expect(s.viewCount, 4);
    expect(s.viewed, isTrue);
  });
}
