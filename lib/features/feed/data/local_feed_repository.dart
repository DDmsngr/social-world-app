import '../domain/entities/post.dart';
import '../domain/repositories/feed_repository.dart';

/// Лента на моках, пока Supabase не поднят. Живёт в памяти: созданный пост
/// остаётся до перезапуска, чтобы можно было пройти сценарий целиком.
class LocalFeedRepository implements FeedRepository {
  /// Автор читается на момент публикации, а не при создании репозитория:
  /// имя появляется только после онбординга, а посты должны пережить его.
  LocalFeedRepository({required this.currentUserId, required this.currentUserName});

  final String Function() currentUserId;
  final String Function() currentUserName;

  late final List<Post> _posts = List.of(_seed);
  var _nextId = 0;

  @override
  Future<List<Post>> loadFeed({String? authorId, int limit = 50}) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final visible = authorId == null
        ? _posts
        : _posts.where((post) => post.authorId == authorId);
    return visible.take(limit).toList(growable: false);
  }

  @override
  Future<Post> createPost({
    required String body,
    PostKind kind = PostKind.text,
    List<String> mediaUrls = const [],
    String? placeTitle,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final post = Post(
      id: 'local-${_nextId++}',
      authorId: currentUserId(),
      authorName: currentUserName(),
      kind: mediaUrls.isEmpty ? kind : PostKind.photo,
      body: body.trim(),
      mediaUrls: mediaUrls,
      placeTitle: placeTitle,
      createdAt: DateTime.now(),
    );
    _posts.insert(0, post);
    return post;
  }

  @override
  Future<Post> toggleLike(Post post) async {
    final liked = !post.likedByMe;
    final updated = post.copyWith(
      likedByMe: liked,
      likeCount: post.likeCount + (liked ? 1 : -1),
    );
    final index = _posts.indexWhere((item) => item.id == post.id);
    if (index != -1) _posts[index] = updated;
    return updated;
  }

  @override
  Future<void> deletePost(String postId) async {
    _posts.removeWhere((post) => post.id == postId);
  }

  static final _seed = <Post>[
    Post(
      id: 'seed-1',
      authorId: 'person-1',
      authorName: 'Алина',
      kind: PostKind.photo,
      body: 'Закат на Приморской. Народу мало, вода тёплая.',
      mediaUrls: const [
        'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=800&q=70',
      ],
      placeTitle: 'Приморская набережная',
      createdAt: DateTime.now().subtract(const Duration(minutes: 24)),
      likeCount: 14,
    ),
    Post(
      id: 'seed-2',
      authorId: 'person-3',
      authorName: 'Саша',
      kind: PostKind.text,
      body: 'Ищу компанию на утренний забег вдоль моря, стартую в семь от '
          'Театральной. Пишите, если кто в теме.',
      placeTitle: 'Театральная площадь',
      createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      likeCount: 6,
    ),
    Post(
      id: 'seed-3',
      authorId: 'person-6',
      authorName: 'Ника',
      kind: PostKind.photo,
      body: 'Новое место с нормальным кофе рядом с Площадью Искусств.',
      mediaUrls: const [
        'https://images.unsplash.com/photo-1495474472287-4d71bcdd2085?w=800&q=70',
      ],
      placeTitle: 'Площадь Искусств',
      createdAt: DateTime.now().subtract(const Duration(hours: 5)),
      likeCount: 31,
    ),
  ];
}
