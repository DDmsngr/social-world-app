import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/features/feed/data/local_feed_repository.dart';

void main() {
  LocalFeedRepository build() => LocalFeedRepository(
    currentUserId: () => 'me',
    currentUserName: () => 'Алексей',
  );

  group('LocalFeedRepository', () {
    test('лента отдаёт посты от новых к старым', () async {
      final posts = await build().loadFeed();

      expect(posts, isNotEmpty);
      for (var i = 1; i < posts.length; i++) {
        expect(
          posts[i].createdAt.isAfter(posts[i - 1].createdAt),
          isFalse,
          reason: 'пост $i новее предыдущего',
        );
      }
    });

    test('созданный пост встаёт первым и подписан текущим автором', () async {
      final repository = build();
      await repository.createPost(body: 'Тестовая публикация');
      final posts = await repository.loadFeed();

      expect(posts.first.body, 'Тестовая публикация');
      expect(posts.first.authorId, 'me');
      expect(posts.first.authorName, 'Алексей');
    });

    test('фильтр по автору отдаёт только его публикации', () async {
      final repository = build();
      await repository.createPost(body: 'Моё');
      final mine = await repository.loadFeed(authorId: 'me');

      expect(mine, hasLength(1));
      expect(mine.single.authorId, 'me');
    });

    test('лайк переключается и счётчик не уходит в минус', () async {
      final repository = build();
      final original = (await repository.loadFeed()).first;

      final liked = await repository.toggleLike(original);
      expect(liked.likedByMe, isTrue);
      expect(liked.likeCount, original.likeCount + 1);

      final unliked = await repository.toggleLike(liked);
      expect(unliked.likedByMe, isFalse);
      expect(unliked.likeCount, original.likeCount);
    });

    test('лайк сохраняется в ленте, а не только в возвращённом объекте', () async {
      final repository = build();
      final first = (await repository.loadFeed()).first;
      await repository.toggleLike(first);

      final reloaded = await repository.loadFeed();
      expect(reloaded.first.likedByMe, isTrue);
    });
  });
}
