import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/entities/comment.dart';
import '../domain/repositories/comments_repository.dart';

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
    final rows = await _client.rpc(
      'post_comments_tree',
      params: {'in_post': postId},
    ) as List<dynamic>;

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
    final row = await _client
        .from('post_comments')
        .insert({
          'post_id': postId,
          'parent_id': parent?.id,
          'author_id': _userId,
          'body': body.trim(),
        })
        .select()
        .single();

    final profile = await _client
        .from('profiles')
        .select('display_name,avatar_url')
        .eq('id', _userId)
        .single();

    return Comment(
      id: row['id'] as String,
      postId: postId,
      parentId: parent?.id,
      authorId: _userId,
      authorName: (profile['display_name'] as String?) ?? 'Без имени',
      authorAvatarUrl: profile['avatar_url'] as String?,
      body: row['body'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
      depth: parent == null ? 0 : parent.depth + 1,
    );
  }

  @override
  Future<Comment> toggleLike(Comment comment) async {
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
    await _client.rpc('soft_delete_own_comment', params: {'in_comment': comment.id});
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
