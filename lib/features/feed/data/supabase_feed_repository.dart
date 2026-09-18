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
    String? placeId,
    String? placeTitle,
    String? routeId,
  }) async {
    // UID фиксируем один раз: между двумя await к _client.auth.currentUser
    // в теории может успеть смениться сессия, а вставлять и читать профиль
    // нужно строго от одного и того же человека.
    final userId = _userId;

    // Файлы уезжают в хранилище до записи в базу: если загрузка сорвётся,
    // в ленте не останется поста с битыми ссылками.
    final uploader = MediaUploader(_client, bucket: 'post-media');
    final mediaUrls = <String>[
      for (final path in mediaPaths) await uploader.upload(path),
    ];

    final row = await _client
        .from('posts')
        .insert({
          'author_id': userId,
          'kind': postKindFor(kind, mediaUrls).name,
          'body': body.trim(),
          'media_urls': mediaUrls,
          'place_id': placeId,
          'route_id': routeId,
        })
        .select()
        .single();

    // Пост уже записан — сбой в этом отдельном чтении не должен превращать
    // успешную публикацию в «не удалось»: имя/аватар просто отобразятся не
    // сразу, и next city_feed их всё равно подтянет джойном.
    String? authorName;
    String? authorAvatarUrl;
    try {
      final profile = await _client
          .from('profiles')
          .select('display_name,avatar_url')
          .eq('id', userId)
          .single();
      authorName = profile['display_name'] as String?;
      authorAvatarUrl = profile['avatar_url'] as String?;
    } catch (_) {
      // Молча — пост уже опубликован, отсутствие имени тут не ошибка публикации.
    }

    return Post(
      id: row['id'] as String,
      authorId: userId,
      authorName: authorName ?? 'Без имени',
      authorAvatarUrl: authorAvatarUrl,
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
