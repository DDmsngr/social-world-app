import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/media/media_uploader.dart';
import '../../../core/permissions/content_permissions.dart';
import '../domain/entities/post.dart';
import '../domain/entities/publish_settings.dart';
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
  Future<Post?> loadPost(String postId) async {
    final rows = await _client.rpc(
      'city_feed',
      params: {'in_post': postId, 'in_limit': 1},
    ) as List<dynamic>;
    if (rows.isEmpty) return null;
    return _fromRow(rows.first as Map<String, dynamic>);
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
          'post_type': postType.name,
          'title': _clean(title),
          'body': body.trim(),
          'body_format': bodyFormat.name,
          'visibility': settings.visibility.wire,
          'show_geo': settings.showGeo,
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
      postType: PostType.parse(row['post_type']),
      title: row['title'] as String?,
      body: row['body'] as String?,
      bodyFormat: BodyFormat.parse(row['body_format']),
      visibility: PostVisibility.parse(row['visibility']),
      showGeo: row['show_geo'] as bool? ?? true,
      mediaUrls: _stringList(row['media_urls']),
      placeId: placeId,
      placeTitle: placeTitle,
      placeLatitude: placeLatitude,
      placeLongitude: placeLongitude,
      routeId: row['route_id'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
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
    final userId = _userId;
    ContentPermissions(viewerId: userId, ownerId: post.authorId).requireOwner();

    final uploader = MediaUploader(_client, bucket: 'post-media');
    final media = [
      ...keepMediaUrls,
      for (final path in newMediaPaths) await uploader.upload(path),
    ];

    // eq('author_id') — второй замок поверх RLS: чужая строка не совпадёт с
    // фильтром, и запрос вернёт пустой результат вместо тихого успеха.
    final updated = await _client
        .from('posts')
        .update({
          'kind': postKindFor(post.kind, media).name,
          'title': _clean(title),
          'body': body.trim(),
          'body_format': (bodyFormat ?? post.bodyFormat).name,
          'visibility': settings.visibility.wire,
          'show_geo': settings.showGeo,
          'media_urls': media,
          'place_id': placeId,
        })
        .eq('id', post.id)
        .eq('author_id', userId)
        .select('id');
    if (updated.isEmpty) {
      throw const PermissionDeniedException('Пост не найден или он не ваш');
    }

    final fresh = await loadPost(post.id);
    if (fresh != null) return fresh;

    // Пост уже сохранён; сюда попадаем только если повторное чтение
    // отработало пусто, — отдаём то, что только что записали.
    return Post(
      id: post.id,
      authorId: post.authorId,
      authorName: post.authorName,
      authorAvatarUrl: post.authorAvatarUrl,
      kind: postKindFor(post.kind, media),
      postType: post.postType,
      title: _clean(title),
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
  }

  @override
  Future<String> uploadInlineImage(String localPath) =>
      MediaUploader(_client, bucket: 'post-media').upload(localPath);

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
  Future<void> deletePost(String postId) async {
    // Свой пост: RLS пропускает только автора, а eq('author_id') не даёт
    // запросу «успешно» удалить ноль строк для чужого.
    final deleted = await _client
        .from('posts')
        .delete()
        .eq('id', postId)
        .eq('author_id', _userId)
        .select('id');
    if (deleted.isEmpty) {
      throw const PermissionDeniedException('Пост не найден или он не ваш');
    }
  }

  Post _fromRow(Map<String, dynamic> row) => Post(
    id: row['id'] as String,
    authorId: row['author_id'] as String,
    authorName: (row['author_name'] as String?) ?? 'Без имени',
    authorAvatarUrl: row['avatar_url'] as String?,
    kind: _kindFrom(row['kind']),
    postType: PostType.parse(row['post_type']),
    title: row['title'] as String?,
    body: row['body'] as String?,
    bodyFormat: BodyFormat.parse(row['body_format']),
    visibility: PostVisibility.parse(row['visibility']),
    showGeo: row['show_geo'] as bool? ?? true,
    mediaUrls: _stringList(row['media_urls']),
    placeId: row['place_id'] as String?,
    placeTitle: row['place_title'] as String?,
    placeLatitude: (row['place_latitude'] as num?)?.toDouble(),
    placeLongitude: (row['place_longitude'] as num?)?.toDouble(),
    routeId: row['route_id'] as String?,
    createdAt: DateTime.parse(row['created_at'] as String),
    editedAt: row['edited_at'] is String
        ? DateTime.parse(row['edited_at'] as String)
        : null,
    likeCount: (row['like_count'] as num?)?.toInt() ?? 0,
    likedByMe: row['liked_by_me'] as bool? ?? false,
    commentCount: (row['comment_count'] as num?)?.toInt() ?? 0,
  );

  String? _clean(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  PostKind _kindFrom(dynamic raw) => PostKind.values.firstWhere(
    (kind) => kind.name == raw,
    orElse: () => PostKind.text,
  );

  List<String> _stringList(dynamic raw) => raw is List
      ? raw.map((item) => item.toString()).toList(growable: false)
      : const [];
}
