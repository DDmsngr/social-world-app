import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/env.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/local_comments_repository.dart';
import '../../data/supabase_comments_repository.dart';
import '../../domain/comment_thread.dart';
import '../../domain/entities/comment.dart';
import '../../domain/repositories/comments_repository.dart';

final commentsRepositoryProvider = Provider<CommentsRepository>((ref) {
  // keepAlive: у заглушки ветки лежат в памяти, пересоздание стёрло бы
  // написанное за сессию.
  ref.keepAlive();
  if (!Env.isConfigured) {
    return LocalCommentsRepository(
      currentUserId: () => ref.read(currentUserProvider)?.id ?? 'local-user',
      currentUserName: () =>
          ref.read(currentUserProvider)?.displayName ?? 'Вы',
    );
  }
  return SupabaseCommentsRepository(Supabase.instance.client);
});

class CommentsController extends AsyncNotifier<List<Comment>> {
  CommentsController(this.postId);

  final String postId;

  @override
  Future<List<Comment>> build() {
    return ref.watch(commentsRepositoryProvider).loadThread(postId);
  }

  /// Новый комментарий встаёт на своё место в дереве сразу, без перезагрузки
  /// ветки: иначе экран прыгает в начало и теряет место, где человек читал.
  Future<void> add(String body, {Comment? parent}) async {
    final comment = await ref
        .read(commentsRepositoryProvider)
        .addComment(postId: postId, body: body, parent: parent);

    state = AsyncValue.data(
      insertIntoThread(state.value ?? const [], comment),
    );
  }

  Future<void> toggleLike(Comment comment) async {
    _replace(await ref.read(commentsRepositoryProvider).toggleLike(comment));
  }

  Future<void> delete(Comment comment) async {
    _replace(await ref.read(commentsRepositoryProvider).deleteComment(comment));
  }

  void _replace(Comment comment) {
    state = AsyncValue.data([
      for (final item in state.value ?? const <Comment>[])
        if (item.id == comment.id) comment else item,
    ]);
  }
}

final commentsProvider =
    AsyncNotifierProvider.family<CommentsController, List<Comment>, String>(
      CommentsController.new,
    );
