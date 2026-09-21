import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/state_message.dart';
import '../../../core/widgets/sw_widgets.dart';
import '../../auth/presentation/providers/auth_providers.dart';
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

  /// Пост, подгруженный с сервера, когда ни в ленте, ни в переданных данных
  /// его нет (ссылка, уведомление, перезапуск).
  Post? _fetched;
  var _fetching = false;
  var _notFound = false;

  @override
  void initState() {
    super.initState();
    if (widget.post == null) _fetchIfMissing();
  }

  Future<void> _fetchIfMissing() async {
    final inFeed = ref.read(feedProvider).value?.any((p) => p.id == widget.postId);
    if (inFeed ?? false) return;

    setState(() => _fetching = true);
    try {
      final post = await ref.read(feedRepositoryProvider).loadPost(widget.postId);
      if (!mounted) return;
      setState(() {
        _fetched = post;
        _notFound = post == null;
        _fetching = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _notFound = true;
        _fetching = false;
      });
    }
  }

  /// Свежая версия из ленты важнее переданной: после лайка, правки или
  /// смены настроек экран показывает то, что лежит в состоянии, а не снимок.
  Post? _currentPost(List<Post> feed) {
    for (final post in feed) {
      if (post.id == widget.postId) return post;
    }
    return widget.post ?? _fetched;
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
    final post = _currentPost(ref.watch(feedProvider).value ?? const <Post>[]);

    // Пост исчез из ленты (удалён автором или скрыт жалобой/блокировкой) —
    // страница закрывается, а не остаётся с призраком поста.
    ref.listen(feedProvider, (previous, next) {
      final was = previous?.value?.any((p) => p.id == widget.postId) ?? false;
      final still = next.value?.any((p) => p.id == widget.postId) ?? false;
      if (next.hasValue && was && !still && mounted) {
        context.canPop() ? context.pop() : context.go(Routes.feed);
      }
    });

    if (post == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Публикация'),
          leading: IconButton(
            onPressed: () =>
                context.canPop() ? context.pop() : context.go(Routes.feed),
            tooltip: 'Назад',
            icon: const Icon(Icons.arrow_back),
          ),
        ),
        body: _fetching
            ? const LoadingView()
            : _notFound
            ? StateMessage(
                title: 'Публикация недоступна',
                text: 'Возможно, её удалили или автор ограничил доступ.',
                icon: Icons.visibility_off_outlined,
                actionLabel: 'Повторить',
                onAction: _fetchIfMissing,
              )
            : const LoadingView(),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(post.isArticle ? 'Статья' : 'Обсуждение'),
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
              loading: () => const LoadingView(),
              error: (_, _) => StateMessage.error(
                title: 'Обсуждение не загрузилось',
                onAction: () => ref.invalidate(commentsProvider(widget.postId)),
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
                    PostCard(
                      post: post,
                      full: true,
                      onComment: _focusNode.requestFocus,
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
