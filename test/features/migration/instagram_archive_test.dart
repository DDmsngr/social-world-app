import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/features/migration/instagram_archive.dart';

void main() {
  group('fixText', () {
    test('чинит кириллицу, записанную байтами Latin-1', () {
      const broken = '\u00d0\u009f\u00d1\u0080\u00d0\u00b8\u00d0\u00b2\u00d0\u00b5\u00d1\u0082';
      expect(fixText(broken), 'Привет');
    });

    test('эмодзи тоже', () {
      expect(fixText('\u00f0\u009f\u0098\u008a'), '😊');
    });

    test('нормальный текст не трогает', () {
      expect(fixText('Привет'), 'Привет');
      expect(fixText('hello'), 'hello');
    });

    test('латиница с акцентом, не похожая на UTF-8, остаётся как есть', () {
      expect(fixText('caf\u00e9'), 'caf\u00e9');
    });
  });

  group('parsePosts', () {
    test('подпись и дата берутся из публикации, видео узнаётся по расширению', () {
      final posts = parsePosts([
        {
          'media': [
            {
              'uri': 'media/posts/202401/a.jpg',
              'creation_timestamp': 1700000000,
              'title': 'Закат',
            },
            {'uri': 'media/posts/202401/b.MP4', 'creation_timestamp': 1700000000},
          ],
        },
      ]);
      expect(posts, hasLength(1));
      expect(posts.first.caption, 'Закат');
      expect(posts.first.media.map((m) => m.video), [false, true]);
      expect(posts.first.takenAt, DateTime.utc(2023, 11, 14, 22, 13, 20));
    });

    test('подпись на уровне публикации важнее подписи файла', () {
      final posts = parsePosts([
        {
          'title': 'Общая',
          'creation_timestamp': 1700000000,
          'media': [
            {'uri': 'a.jpg', 'title': 'Своя'},
          ],
        },
      ]);
      expect(posts.first.caption, 'Общая');
    });

    test('ролики лежат в объекте с одним списком', () {
      final posts = parsePosts({
        'ig_reels_media': [
          {
            'media': [
              {'uri': 'media/reels/r.mp4', 'creation_timestamp': 1700000000},
            ],
          },
        ],
      });
      expect(posts, hasLength(1));
      expect(posts.first.media.single.video, isTrue);
    });

    test('публикации без файлов и мусор пропускаются', () {
      expect(parsePosts([{'media': []}, 5, {'x': 1}]), isEmpty);
      expect(parsePosts(null), isEmpty);
    });
  });

  group('контакты', () {
    test('подписчики: ник в value, подписки: ник в title', () {
      final followers = parseFollowers([
        {
          'title': '',
          'string_list_data': [
            {'href': 'https://x/rigbi80', 'value': 'rigbi80', 'timestamp': 1},
          ],
        },
      ]);
      final following = parseFollowing({
        'relationships_following': [
          {
            'title': 'mishqa_kr',
            'string_list_data': [
              {'href': 'https://x/_u/mishqa_kr', 'timestamp': 1},
            ],
          },
          {
            'title': 'RigBi80',
            'string_list_data': [
              {'href': 'https://x/_u/rigbi80', 'timestamp': 1},
            ],
          },
        ],
      });
      expect(followers, ['rigbi80']);
      expect(following, ['mishqa_kr', 'RigBi80']);

      final merged = mergeContacts(followers: followers, following: following);
      expect(merged.map((c) => c.handle), ['mishqa_kr', 'rigbi80']);
      final rigbi = merged.firstWhere((c) => c.handle == 'rigbi80');
      expect(rigbi.mutual, isTrue);
      expect(merged.first.mutual, isFalse);
    });
  });

  group('прочее', () {
    test('фото профиля', () {
      expect(
        parseProfilePhoto({
          'ig_profile_picture': [
            {'uri': 'media/profile/202406/p.jpg'},
          ],
        }),
        'media/profile/202406/p.jpg',
      );
    });

    test('ник из имени файла выгрузки', () {
      expect(
        handleFromArchiveName(r'D:\temp\instagram-axelnewton-2026-10-05-4R2REl96.zip'),
        'axelnewton',
      );
      expect(handleFromArchiveName('архив.zip'), isNull);
    });

    test('какие файлы выгрузки читаем', () {
      expect(isPostsFile('your_instagram_activity/media/posts_1.json'), isTrue);
      expect(isPostsFile('your_instagram_activity/media/reels.json'), isTrue);
      expect(isPostsFile('your_instagram_activity/media/stories.json'), isFalse);
      expect(isFollowersFile('connections/followers_and_following/followers_2.json'), isTrue);
      expect(isFollowingFile('connections/followers_and_following/following.json'), isTrue);
    });

    test('заголовок статьи из длинной подписи', () {
      expect(articleTitle('\n\nПервая строка\nвторая'), 'Первая строка');
      expect(articleTitle('а' * 200).length, 80);
    });
  });
}
