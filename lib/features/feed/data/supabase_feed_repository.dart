import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/media/media_uploader.dart';
import '../domain/entities/post.dart';
import '../domain/repositories/feed_repository.dart';

class SupabaseFeedRepository implements FeedRepository {
  SupabaseFeedRepository(this._client);

  final SupabaseClient _client;

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw const AuthException('Нет активной сессии');
    return id;
  }

  @override
  Future<List<Post>> loadFeed({String? authorId, int limit = 50}) async {
    final rows = await _client.rpc(
      'city_feed',
      params: {'in_author': authorId, 'in_limit': limit},
    ) as List<dynamic>;

    return rows
        .map((row) => _fromRow(row as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<Post> createPost({
    required String body,
    PostKind kind = PostKind.text,
    List<String> mediaPaths = const [],
    String? placeTitle,
    String? routeId,
  }) async {
    // Файлы уезжают в хранилище до записи в базу: если загрузка сорвётся,
    // в ленте не останется поста с битыми ссылками.
    final uploader = MediaUploader(_client, bucket: 'post-media');
    final mediaUrls = <String>[
      for (final path in mediaPaths) await uploader.upload(path),
    ];

    // Без place_id выбранное в форме место живёт только до перезагрузки ленты:
    // city_feed берёт название джойном по places.
    final placeId = placeTitle == null
        ? null
        : await _client
              .from('places')
              .select('id')
              .eq('title', placeTitle)
              .maybeSingle()
              .then((row) => row?['id'] as String?);

    final row = await _client
        .from('posts')
        .insert({
          'author_id': _userId,
          'kind': postKindFor(kind, mediaUrls).name,
          'body': body.trim(),
          'media_urls': mediaUrls,
          'place_id': placeId,
          'route_id': routeId,
        })
        .select()
        .single();

    final profile = await _client
        .from('profiles')
        .select('display_name,avatar_url')
        .eq('id', _userId)
        .single();

    return Post(
      id: row['id'] as String,
      authorId: _userId,
      authorName: (profile['display_name'] as String?) ?? 'Без имени',
      authorAvatarUrl: profile['avatar_url'] as String?,
      kind: _kindFrom(row['kind']),
      body: row['body'] as String?,
      mediaUrls: _stringList(row['media_urls']),
      placeTitle: placeTitle,
      routeId: row['route_id'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }

  @override
  Future<Post> toggleLike(Post post) async {
    if (post.likedByMe) {
      await _client.from('post_likes').delete().match({
        'post_id': post.id,
        'profile_id': _userId,
      });
    } else {
      await _client.from('post_likes').insert({
        'post_id': post.id,
        'profile_id': _userId,
      });
    }

    final liked = !post.likedByMe;
    return post.copyWith(
      likedByMe: liked,
      likeCount: post.likeCount + (liked ? 1 : -1),
    );
  }

  @override
  Future<void> deletePost(String postId) =>
      _client.from('posts').delete().eq('id', postId);

  Post _fromRow(Map<String, dynamic> row) => Post(
    id: row['id'] as String,
    authorId: row['author_id'] as String,
    authorName: (row['author_name'] as String?) ?? 'Без имени',
    authorAvatarUrl: row['avatar_url'] as String?,
    kind: _kindFrom(row['kind']),
    body: row['body'] as String?,
    mediaUrls: _stringList(row['media_urls']),
    placeTitle: row['place_title'] as String?,
    routeId: row['route_id'] as String?,
    createdAt: DateTime.parse(row['created_at'] as String),
    likeCount: (row['like_count'] as num?)?.toInt() ?? 0,
    likedByMe: row['liked_by_me'] as bool? ?? false,
    commentCount: (row['comment_count'] as num?)?.toInt() ?? 0,
  );

  PostKind _kindFrom(dynamic raw) => PostKind.values.firstWhere(
    (kind) => kind.name == raw,
    orElse: () => PostKind.text,
  );

  List<String> _stringList(dynamic raw) => raw is List
      ? raw.map((item) => item.toString()).toList(growable: false)
      : const [];
}
