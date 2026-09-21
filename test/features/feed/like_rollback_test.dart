import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/features/auth/domain/entities/app_user.dart';
import 'package:social_world/features/auth/presentation/providers/auth_providers.dart';
import 'package:social_world/features/feed/domain/entities/post.dart';
import 'package:social_world/features/feed/domain/entities/publish_settings.dart';
import 'package:social_world/features/feed/domain/repositories/feed_repository.dart';
import 'package:social_world/features/feed/presentation/providers/feed_providers.dart';

final _post = Post(
  id: 'post-1',
  authorId: 'user-1',
  authorName: 'Алина',
  kind: PostKind.text,
  createdAt: DateTime(2026, 9, 20),
  likeCount: 3,
);

/// Лента из одного поста, у которой лайк всегда падает — так ведёт себя
/// боевой репозиторий без сети.
class _FailingFeedRepository implements FeedRepository {
  var likeCalls = 0;

  @override
  Future<List<Post>> loadFeed({String? authorId, int limit = 50}) async => [
    _post,
  ];

  @override
  Future<Post> toggleLike(Post post) async {
    likeCalls++;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    throw Exception('нет сети');
  }

  @override
  Future<Post?> loadPost(String postId) async => _post;

  @override
  Future<Post> updatePost(
    Post post, {
    required String body,
    String? title,
    BodyFormat? bodyFormat,
    required PublishSettings settings,
    required List<String> keepMediaUrls,
    List<String> newMediaPaths = const [],
    String? placeId,
    String? placeTitle,
    double? placeLatitude,
    double? placeLongitude,
  }) async => _post;

  @override
  Future<String> uploadInlineImage(String localPath) async => localPath;

  @override
  Future<Post> createPost({
    required String body,
    PostKind kind = PostKind.text,
    PostType postType = PostType.moment,
    String? title,
    BodyFormat bodyFormat = BodyFormat.plain,
    PublishSettings settings = PublishSettings.defaults,
    List<String> mediaPaths = const [],
    String? placeId,
    String? placeTitle,
    double? placeLatitude,
    double? placeLongitude,
    String? routeId,
  }) async => _post;

  @override
  Future<void> deletePost(String postId) async {}
}

Post _first(ProviderContainer container) =>
    container.read(feedProvider).value!.single;

void main() {
  late _FailingFeedRepository repository;
  late ProviderContainer container;

  setUp(() async {
    repository = _FailingFeedRepository();
    container = ProviderContainer(
      overrides: [
        feedRepositoryProvider.overrideWithValue(repository),
        currentUserProvider.overrideWithValue(
          const AppUser(id: 'user-1', displayName: 'Я'),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(feedProvider.future);
  });

  test('неудавшийся лайк откатывается, а не остаётся закрашенным', () async {
    final saved = await container.read(feedProvider.notifier).toggleLike(_post);

    expect(saved, isFalse, reason: 'экран должен узнать о неудаче');
    expect(_first(container).likedByMe, isFalse);
    expect(_first(container).likeCount, 3, reason: 'счётчик вернулся назад');
  });

  test('второй тап по тому же посту не улетает, пока первый в полёте', () async {
    final first = container.read(feedProvider.notifier).toggleLike(_post);
    final second = container.read(feedProvider.notifier).toggleLike(_post);
    await Future.wait([first, second]);

    // Иначе лайк и его снятие гоняются наперегонки и в базе остаётся
    // случайный из двух.
    expect(repository.likeCalls, 1);
  });
}
