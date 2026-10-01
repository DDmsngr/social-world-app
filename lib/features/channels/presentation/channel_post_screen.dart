import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/state_message.dart';
import '../../../core/widgets/sw_widgets.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../feed/data/supabase_comments_repository.dart';
import '../../feed/domain/comment_thread.dart';
import '../../feed/domain/entities/comment.dart';
import '../../feed/presentation/providers/comments_providers.dart';
import '../../feed/presentation/widgets/comment_composer.dart';
import '../../feed/presentation/widgets/comment_tile.dart';
import 'providers/channel_providers.dart';
import 'widgets/channel_post_card.dart';

/// Пост канала и обсуждение под ним деревом — тот же механизм, что у постов
/// ленты: ветки, сворачивание, лайки, «лучшие сверху».
class ChannelPostScreen extends ConsumerStatefulWidget {
  const ChannelPostScreen({super.key, required this.channelId, required this.postId});

  final String channelId;
  final String postId;

  @override
  ConsumerState<ChannelPostScreen> createState() => _ChannelPostScreenState();
}

class _ChannelPostScreenState extends ConsumerState<ChannelPostScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _collapsed = <String>{};
  Comment? _replyTo;
  var _sending = false;

  String get _key => channelThreadKey(widget.postId);

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await ref.read(commentsProvider(_key).notifier).add(text, parent: _replyTo);
      ref.read(channelPostsProvider(widget.channelId).notifier).bumpComments(widget.postId, 1);
      if (!mounted) return;
      _controller.clear();
      setState(() {
        _replyTo = null;
        _sending = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось отправить комментарий')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final posts = ref.watch(channelPostsProvider(widget.channelId)).value ?? const [];
    final post = posts.where((p) => p.message.id == widget.postId).firstOrNull;
    final thread = ref.watch(commentsProvider(_key));
    final myId = ref.watch(currentUserProvider)?.id;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Обсуждение'),
        leading: IconButton(
          onPressed: () => context.canPop()
              ? context.pop()
              : context.go(Routes.channel(widget.channelId)),
          tooltip: 'Назад',
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: thread.when(
              loading: () => const LoadingView(),
              error: (_, _) => StateMessage.error(
                title: 'Обсуждение не загрузилось',
                onAction: () => ref.invalidate(commentsProvider(_key)),
              ),
              data: (comments) {
                final rows = visibleThread(comments, _collapsed);
                return ListView(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 8, AppSpacing.gutter, 16),
                  children: [
                    if (post != null) ChannelPostCard(post: post, full: true),
                    const SizedBox(height: 8),
                    const SectionLabel('Обсуждение'),
                    const SizedBox(height: 10),
                    if (rows.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          'Комментариев пока нет. Напишите первым.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    for (final row in rows)
                      CommentTile(
                        comment: row.comment,
                        hiddenReplies: row.hiddenReplies,
                        collapsed: row.collapsed,
                        isMine: row.comment.authorId == myId,
                        onLike: () => ref.read(commentsProvider(_key).notifier).toggleLike(row.comment),
                        onReply: () {
                          setState(() => _replyTo = row.comment);
                          _focusNode.requestFocus();
                        },
                        onToggleCollapse: () => setState(() {
                          if (!_collapsed.remove(row.comment.id)) _collapsed.add(row.comment.id);
                        }),
                        onDelete: () => ref.read(commentsProvider(_key).notifier).delete(row.comment),
                      ),
                  ],
                );
              },
            ),
          ),
          CommentComposer(
            controller: _controller,
            focusNode: _focusNode,
            replyTo: _replyTo,
            sending: _sending,
            onCancelReply: () => setState(() => _replyTo = null),
            onSend: _send,
          ),
        ],
      ),
    );
  }
}
