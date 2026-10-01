import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/entities/comment.dart';
import '../domain/repositories/comments_repository.dart';

/// Ключ ветки для поста канала. Обсуждения постов и каналов устроены
/// одинаково (дерево, лайки, мягкое удаление), различаются только таблицы,
/// поэтому экран и контроллер общие, а ветку выбирает префикс.
String channelThreadKey(String messageId) => 'ch:$messageId';

String? channelPostOf(String threadKey) =>
    threadKey.startsWith('ch:') ? threadKey.substring(3) : null;

class SupabaseCommentsRepository implements CommentsRepository {
  SupabaseCommentsRepository(this._client);

  final SupabaseClient _client;

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw const AuthException('Нет активной сессии');
    return id;
  }

  @override
  Future<List<Comment>> loadThread(String postId) async {
    final channelPost = channelPostOf(postId);
    final rows = await (channelPost == null
            ? _client.rpc('post_comments_tree', params: {'in_post': postId})
            : _client.rpc('channel_comments_tree', params: {'in_message': channelPost}))
        as List<dynamic>;

    return rows
        .map((row) => _fromRow(postId, row as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<Comment> addComment({
    required String postId,
    required String body,
    Comment? parent,
  }) async {
    final userId = _userId;
    final channelPost = channelPostOf(postId);
    final Map<String, dynamic> row;
    if (channelPost != null) {
      final rows = await _client.rpc(
        'channel_comment_add',
        params: {'in_message': channelPost, 'in_parent': parent?.id, 'in_body': body.trim()},
      ) as List<dynamic>;
      row = {...rows.first as Map<String, dynamic>, 'body': body.trim()};
    } else {
      row = await _client
          .from('post_comments')
          .insert({
            'post_id': postId,
            'parent_id': parent?.id,
            'author_id': userId,
            'body': body.trim(),
          })
          .select()
          .single();
    }

    // Комментарий уже создан — падение этого чтения не должно превращать
    // успешную отправку в ошибку.
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
      // Молча — комментарий уже отправлен.
    }

    return Comment(
      id: row['id'] as String,
      postId: postId,
      parentId: parent?.id,
      authorId: userId,
      authorName: authorName ?? 'Без имени',
      authorAvatarUrl: authorAvatarUrl,
      body: row['body'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
      depth: parent == null ? 0 : parent.depth + 1,
    );
  }

  @override
  Future<Comment> toggleLike(Comment comment) async {
    if (channelPostOf(comment.postId) != null) {
      final liked = await _client.rpc(
        'channel_comment_toggle_like',
        params: {'in_comment': comment.id},
      ) as bool;
      return comment.copyWith(
        likedByMe: liked,
        likeCount: comment.likeCount + (liked ? 1 : -1),
      );
    }
    if (comment.likedByMe) {
      await _client.from('comment_likes').delete().match({
        'comment_id': comment.id,
        'profile_id': _userId,
      });
    } else {
      await _client.from('comment_likes').insert({
        'comment_id': comment.id,
        'profile_id': _userId,
      });
    }

    final liked = !comment.likedByMe;
    return comment.copyWith(
      likedByMe: liked,
      likeCount: comment.likeCount + (liked ? 1 : -1),
    );
  }

  @override
  Future<Comment> deleteComment(Comment comment) async {
    // RPC, а не update({'deleted_at': ...}) отсюда же: удаление должно
    // стереть body/media_urls по-настоящему, а не только проставить дату —
    // иначе текст «удалённого» комментария остаётся читаемым прямым select
    // к таблице, в обход RPC, которая его маскирует.
    await _client.rpc(
      channelPostOf(comment.postId) == null
          ? 'soft_delete_own_comment'
          : 'channel_comment_delete',
      params: {'in_comment': comment.id},
    );
    return comment.copyWith(deleted: true);
  }

  Comment _fromRow(String postId, Map<String, dynamic> row) => Comment(
    id: row['id'] as String,
    postId: postId,
    parentId: row['parent_id'] as String?,
    authorId: row['author_id'] as String,
    authorName: (row['author_name'] as String?) ?? 'Без имени',
    authorAvatarUrl: row['avatar_url'] as String?,
    body: row['body'] as String?,
    mediaUrls: row['media_urls'] is List
        ? (row['media_urls'] as List)
              .map((item) => item.toString())
              .toList(growable: false)
        : const [],
    createdAt: DateTime.parse(row['created_at'] as String),
    depth: (row['depth'] as num?)?.toInt() ?? 0,
    likeCount: (row['like_count'] as num?)?.toInt() ?? 0,
    likedByMe: row['liked_by_me'] as bool? ?? false,
    deleted: row['deleted'] as bool? ?? false,
  );
}
