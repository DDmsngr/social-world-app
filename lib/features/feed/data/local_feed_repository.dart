import '../../../core/permissions/content_permissions.dart';
import '../../discover/domain/entities/city.dart';
import '../domain/entities/post.dart';
import '../domain/entities/publish_settings.dart';
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

  /// Видимость проверяется и в моках: без подписок «подписчикам» здесь
  /// значит то же, что «всем», а «только мне» скрывает пост от других.
  bool _visible(Post post) =>
      post.visibility != PostVisibility.onlyMe ||
      post.authorId == currentUserId();

  @override
  Future<List<Post>> loadFeed({String? authorId, int limit = 50, String? city}) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    // У заглушки все авторы — из пилотного города: в режиме «Город» с другим
    // городом лента честно пустая.
    if (city != null && city != Cities.fallback.name) return const [];
    final visible = _posts.where(
      (post) => _visible(post) && (authorId == null || post.authorId == authorId),
    );
    return visible.take(limit).toList(growable: false);
  }

  @override
  Future<Post?> loadPost(String postId) async {
    for (final post in _posts) {
      if (post.id == postId && _visible(post)) return post;
    }
    return null;
  }

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
    String? questId,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    // Хранилища в моках нет, поэтому ссылкой служит сам путь к файлу — этого
    // хватает, чтобы пройти сценарий публикации целиком.
    final post = Post(
      id: 'local-${_nextId++}',
      authorId: currentUserId(),
      authorName: currentUserName(),
      kind: postKindFor(kind, mediaPaths),
      postType: postType,
      title: title?.trim().isEmpty ?? true ? null : title!.trim(),
      body: body.trim(),
      bodyFormat: bodyFormat,
      visibility: settings.visibility,
      showGeo: settings.showGeo,
      mediaUrls: mediaPaths,
      placeId: placeId,
      placeTitle: placeTitle,
      placeLatitude: placeLatitude,
      placeLongitude: placeLongitude,
      routeId: routeId,
      createdAt: DateTime.now(),
    );
    _posts.insert(0, post);
    return post;
  }

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
  }) async {
    ContentPermissions(
      viewerId: currentUserId(),
      ownerId: post.authorId,
    ).requireOwner();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    final media = [...keepMediaUrls, ...newMediaPaths];
    final updated = Post(
      id: post.id,
      authorId: post.authorId,
      authorName: post.authorName,
      authorAvatarUrl: post.authorAvatarUrl,
      kind: postKindFor(post.kind, media),
      postType: post.postType,
      title: title?.trim().isEmpty ?? true ? null : title!.trim(),
      body: body.trim(),
      bodyFormat: bodyFormat ?? post.bodyFormat,
      visibility: settings.visibility,
      showGeo: settings.showGeo,
      mediaUrls: media,
      placeId: placeId,
      placeTitle: placeTitle,
      placeLatitude: placeLatitude,
      placeLongitude: placeLongitude,
      routeId: post.routeId,
      createdAt: post.createdAt,
      editedAt: DateTime.now(),
      likeCount: post.likeCount,
      likedByMe: post.likedByMe,
      commentCount: post.commentCount,
    );
    final index = _posts.indexWhere((item) => item.id == post.id);
    if (index != -1) _posts[index] = updated;
    return updated;
  }

  @override
  Future<String> uploadInlineImage(String localPath) async => localPath;

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
    final index = _posts.indexWhere((post) => post.id == postId);
    if (index == -1) return;
    ContentPermissions(
      viewerId: currentUserId(),
      ownerId: _posts[index].authorId,
    ).requireOwner();
    _posts.removeAt(index);
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
      // Столько же веток лежит в заглушке комментариев: иначе карточка в ленте
      // спорит с тем, что видно внутри обсуждения.
      commentCount: 4,
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
    Post(
      id: 'seed-4',
      authorId: 'person-1',
      authorName: 'Алина',
      kind: PostKind.text,
      postType: PostType.article,
      title: 'Три тихих места для рассвета',
      bodyFormat: BodyFormat.markdown,
      body: '## Почему рассвет\n\nК шести утра город **ещё пустой**, и вода '
          'спокойная.\n\n- Приморская набережная\n- Дендрарий, нижний вход\n'
          '- Маяк у порта\n\n> Приходите без телефона, хотя бы на полчаса.\n',
      placeTitle: 'Приморская набережная',
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
      likeCount: 9,
    ),
  ];
}
