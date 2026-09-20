import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/sw_widgets.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../moderation/domain/entities/report_reason.dart';
import '../../moderation/presentation/widgets/report_sheet.dart';
import '../domain/comment_thread.dart';
import '../domain/entities/comment.dart';
import '../domain/entities/post.dart';
import 'providers/comments_providers.dart';
import 'providers/feed_providers.dart';
import 'widgets/comment_tile.dart';
import 'widgets/post_card.dart';

/// Публикация и обсуждение под ней ветками.
class PostDetailScreen extends ConsumerStatefulWidget {
  const PostDetailScreen({super.key, required this.postId, this.post});

  final String postId;

  /// Пост приходит из ленты, чтобы не ждать второго запроса ради шапки.
  /// По прямой ссылке его нет — тогда ищем в уже загруженной ленте.
  final Post? post;

  @override
  ConsumerState<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends ConsumerState<PostDetailScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _collapsed = <String>{};
  Comment? _replyTo;
  var _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Post? get _post {
    if (widget.post != null) return widget.post;
    final feed = ref.read(feedProvider).value ?? const <Post>[];
    for (final post in feed) {
      if (post.id == widget.postId) return post;
    }
    return null;
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() => _sending = true);
    try {
      await ref
          .read(commentsProvider(widget.postId).notifier)
          .add(text, parent: _replyTo);
      ref.read(feedProvider.notifier).bumpCommentCount(widget.postId, 1);

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

  void _reply(Comment comment) {
    setState(() => _replyTo = comment);
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final thread = ref.watch(commentsProvider(widget.postId));
    final myId = ref.watch(currentUserProvider)?.id;
    final post = _post;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Обсуждение'),
        leading: IconButton(
          onPressed: () =>
              context.canPop() ? context.pop() : context.go(Routes.feed),
          tooltip: 'Назад',
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: thread.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.gutter),
                  child: Text(
                    'Обсуждение не загрузилось. Проверьте соединение.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ),
              data: (comments) {
                final rows = visibleThread(comments, _collapsed);

                return ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.gutter,
                    12,
                    AppSpacing.gutter,
                    16,
                  ),
                  children: [
                    if (post != null)
                      PostCard(
                        post: post,
                        onLike: () async {
                          final saved = await ref
                              .read(feedProvider.notifier)
                              .toggleLike(post);
                          if (saved || !context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Лайк не сохранился — нет связи'),
                            ),
                          );
                        },
                        onComment: _focusNode.requestFocus,
                        onReport: () async {
                          final sent = await showReportSheet(
                            context,
                            target: ReportTarget.post,
                            targetId: post.id,
                            subject:
                                '${post.authorName}: ${post.body ?? 'публикация'}',
                          );
                          if (!sent || !context.mounted) return;
                          ref.read(feedProvider.notifier).hide(post.id);
                          context.pop();
                        },
                      ),
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
                        onLike: () => ref
                            .read(commentsProvider(widget.postId).notifier)
                            .toggleLike(row.comment),
                        onReply: () => _reply(row.comment),
                        onToggleCollapse: () => setState(() {
                          if (!_collapsed.remove(row.comment.id)) {
                            _collapsed.add(row.comment.id);
                          }
                        }),
                        onDelete: () => ref
                            .read(commentsProvider(widget.postId).notifier)
                            .delete(row.comment),
                      ),
                  ],
                );
              },
            ),
          ),
          _Composer(
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

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.replyTo,
    required this.sending,
    required this.onCancelReply,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final Comment? replyTo;
  final bool sending;
  final VoidCallback onCancelReply;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.ink2,
          border: Border(top: BorderSide(color: AppColors.hair)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 8, 12, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (replyTo != null)
                Row(
                  children: [
                    Icon(Icons.reply, size: 14, color: AppColors.primaryTint),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Ответ: ${replyTo!.authorName}',
                        style: AppTypography.serif(13, color: AppColors.primaryTint),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      onPressed: onCancelReply,
                      tooltip: 'Отменить ответ',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close, size: 16),
                    ),
                  ],
                ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      maxLines: 4,
                      minLines: 1,
                      maxLength: 2000,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Написать комментарий',
                        counterText: '',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: sending ? null : onSend,
                    tooltip: 'Отправить',
                    icon: sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(Icons.send, color: AppColors.primaryTint),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
