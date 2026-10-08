import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/debug/app_log.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/state_message.dart';
import '../../../core/widgets/sw_widgets.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../domain/comment_thread.dart';
import '../domain/entities/comment.dart';
import '../domain/entities/post.dart';
import '../domain/repositories/comments_repository.dart';
import 'providers/comments_providers.dart';
import 'providers/feed_providers.dart';
import 'widgets/comment_composer.dart';
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
    // Ветка могла остаться в памяти от прошлого открытия этого же поста
    // (например, тап по уведомлению поверх открытого поста): без обновления
    // новые ответы не видны. Старые комментарии на экране остаются, пока
    // грузятся свежие.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.invalidate(commentsProvider(widget.postId));
    });
  }

  /// По ссылке или уведомлению пост всегда берём свежим с сервера: копия в
  /// ленте могла устареть (07.10: Вике пришёл пуш о лайке, она открыла пост —
  /// а лайка нет, пока не перезапустит приложение). Свежая версия заменяет и
  /// копию в ленте.
  Future<void> _fetchIfMissing() async {
    final inFeed = ref.read(feedProvider).value?.any((p) => p.id == widget.postId) ?? false;

    if (!inFeed) setState(() => _fetching = true);
    try {
      final post = await ref.read(feedRepositoryProvider).loadPost(widget.postId);
      if (!mounted) return;
      if (inFeed) {
        if (post != null) ref.read(feedProvider.notifier).replacePost(post);
        return;
      }
      setState(() {
        _fetched = post;
        _notFound = post == null;
        _fetching = false;
      });
    } catch (_) {
      if (!mounted || inFeed) return;
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
  /// Картинки, приложенные к будущему комментарию (пути на телефоне).
  final _media = <String>[];
  final _picker = ImagePicker();

  Future<void> _pickPhotos() async {
    try {
      final room = maxCommentMedia - _media.length;
      if (room <= 0) return;
      final picked = await _picker.pickMultiImage(
        imageQuality: 85,
        maxWidth: 2048,
        maxHeight: 2048,
        limit: room,
      );
      if (picked.isEmpty || !mounted) return;
      setState(() => _media.addAll(picked.take(room).map((file) => file.path)));
    } catch (error) {
      AppLog.add('Фото для комментария: $error');
    }
  }

  /// GIF берётся файлом как есть: через обычную галерею Android пересжимает
  /// кадры, и анимация пропадает.
  Future<void> _pickGif() async {
    try {
      if (_media.length >= maxCommentMedia) return;
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['gif'],
      );
      final path = files.isEmpty ? null : files.first.path;
      if (path == null || !mounted) return;
      setState(() => _media.add(path));
    } catch (error) {
      AppLog.add('GIF для комментария: $error');
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty && _media.isEmpty) return;

    setState(() => _sending = true);
    try {
      await ref
          .read(commentsProvider(widget.postId).notifier)
          .add(text, parent: _replyTo, mediaPaths: List.of(_media));
      ref.read(feedProvider.notifier).bumpCommentCount(widget.postId, 1);

      if (!mounted) return;
      _controller.clear();
      setState(() {
        _replyTo = null;
        _media.clear();
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
                        onDislike: () => ref
                            .read(commentsProvider(widget.postId).notifier)
                            .toggleDislike(row.comment),
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
          CommentComposer(
            controller: _controller,
            focusNode: _focusNode,
            replyTo: _replyTo,
            sending: _sending,
            onCancelReply: () => setState(() => _replyTo = null),
            onSend: _send,
            attachments: _media,
            onPickPhotos: _pickPhotos,
            onPickGif: _pickGif,
            onRemoveAttachment: (index) => setState(() => _media.removeAt(index)),
          ),
        ],
      ),
    );
  }
}
