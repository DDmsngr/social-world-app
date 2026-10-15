import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/core/links/deep_links.dart';
import 'package:social_world/features/feed/domain/entities/post.dart';
import 'package:social_world/features/feed/presentation/providers/muted_hashtags.dart';

Post _post(String body) => Post(
  id: 'p',
  authorId: 'a',
  authorName: 'Вера',
  kind: PostKind.text,
  createdAt: DateTime(2026, 10, 15),
  body: body,
);

void main() {
  group('скрытые теги', () {
    test('пост с тегом из игнор-листа скрывается, регистр не важен', () {
      expect(
        hasMutedHashtag(_post('Хинкали #Кухня #Грузия'), {'кухня'}),
        isTrue,
      );
    });

    test('похожий тег не считается', () {
      expect(hasMutedHashtag(_post('#кухнямира'), {'кухня'}), isFalse);
    });

    test('пустой игнор-лист ничего не скрывает', () {
      expect(hasMutedHashtag(_post('#кухня'), const {}), isFalse);
    });
  });

  group('уведомление о комментарии', () {
    test('ведёт на пост с комментарием в адресе', () {
      expect(
        DeepLinks.locationFor(LinkTarget.post, 'p1', comment: 'c1'),
        '${DeepLinks.locationFor(LinkTarget.post, 'p1')}?comment=c1',
      );
    });

    test('без комментария — просто пост', () {
      expect(
        DeepLinks.locationFor(LinkTarget.post, 'p1', comment: ''),
        isNot(contains('comment')),
      );
    });
  });
}
