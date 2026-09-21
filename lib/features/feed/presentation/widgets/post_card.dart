import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/text/markdown_preview.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/markdown_view.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../profile/domain/profile_models.dart';
import '../../../routes/presentation/widgets/route_post_preview.dart';
import '../../../saved/saved.dart';
import '../../domain/entities/post.dart';
import '../post_actions.dart';
import '../providers/feed_providers.dart';
import 'post_media.dart';

enum _PostMenu {
  edit,
  settings,
  save,
  share,
  delete,
  report,
  hideAuthor,
  blockAuthor,
}

/// Карточка поста — одна на ленту, обсуждение, профиль и страницу места.
///
/// Меню зависит от того, чей это пост: у своего — управление (правка,
/// настройки публикации, удаление), у чужого — жалоба, скрытие и блокировка
/// автора. Решение принимает [postPermissions], а не сравнение id здесь.
class PostCard extends ConsumerWidget {
  const PostCard({
    super.key,
    required this.post,
    this.onComment,

    /// true — на странице самого поста: статья и Markdown показываются целиком.
    this.full = false,
  });

  final Post post;
  final VoidCallback? onComment;
  final bool full;

  void _openDetail(BuildContext context) =>
      context.push('${Routes.posts}/${post.id}', extra: post);

  Future<void> _like(BuildContext context, WidgetRef ref) async {
    final saved = await ref.read(feedProvider.notifier).toggleLike(post);
    if (saved || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Лайк не сохранился — нет связи')),
    );
  }

  Future<void> _onMenu(BuildContext context, WidgetRef ref, _PostMenu item) {
    switch (item) {
      case _PostMenu.edit:
        return editPost(context, ref, post);
      case _PostMenu.settings:
        return changePostSettings(context, ref, post);
      case _PostMenu.save:
        return toggleSavePost(context, ref, post);
      case _PostMenu.share:
        return sharePost(context, post);
      case _PostMenu.delete:
        return deleteOwnPost(context, ref, post);
      case _PostMenu.report:
        return reportPost(context, ref, post);
      case _PostMenu.hideAuthor:
        return blockAuthor(
          context,
          ref,
          userId: post.authorId,
          name: post.authorName,
          avatarUrl: post.authorAvatarUrl,
          kind: BlockKind.mute,
        );
      case _PostMenu.blockAuthor:
        return blockAuthor(
          context,
          ref,
          userId: post.authorId,
          name: post.authorName,
          avatarUrl: post.authorAvatarUrl,
          kind: BlockKind.block,
        );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissions = postPermissions(ref, post);
    final isSaved =
        ref.watch(savedProvider).value?.contains(savedKey(SavedKind.post, post.id)) ??
        false;
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.hair),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 4, 10),
            child: Row(
              children: [
                UserAvatar(
                  name: post.authorName,
                  url: post.authorAvatarUrl,
                  userId: post.authorId,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: () => openProfile(context, post.authorId),
                    borderRadius: BorderRadius.circular(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(post.authorName, style: theme.textTheme.titleLarge),
                        Text(
                          [
                            _relativeTime(post.createdAt),
                            if (post.editedAt != null) 'изменено',
                            if (post.placeTitle != null) post.placeTitle!,
                          ].join(' · '),
                          style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
                if (permissions.isOwner && post.visibility != PostVisibility.everyone)
                  Tooltip(
                    message: post.visibility.label,
                    child: Icon(
                      post.visibility == PostVisibility.onlyMe
                          ? Icons.lock_outline
                          : Icons.group_outlined,
                      size: 16,
                      color: AppColors.textFaint,
                    ),
                  ),
                PopupMenuButton<_PostMenu>(
                  tooltip: 'Действия',
                  icon: Icon(Icons.more_horiz, color: AppColors.textFaint),
                  color: AppColors.ink2,
                  onSelected: (item) => _onMenu(context, ref, item),
                  itemBuilder: (_) => [
                    if (permissions.canEdit && !post.isRoute)
                      const PopupMenuItem(
                        value: _PostMenu.edit,
                        child: Text('Редактировать'),
                      ),
                    if (permissions.canChangeVisibility)
                      const PopupMenuItem(
                        value: _PostMenu.settings,
                        child: Text('Настройки публикации'),
                      ),
                    PopupMenuItem(
                      value: _PostMenu.save,
                      child: Text(isSaved ? 'Убрать из сохранённого' : 'Сохранить'),
                    ),
                    const PopupMenuItem(
                      value: _PostMenu.share,
                      child: Text('Поделиться'),
                    ),
                    if (permissions.canDelete)
                      const PopupMenuItem(
                        value: _PostMenu.delete,
                        child: Text('Удалить'),
                      ),
                    if (permissions.canReport)
                      const PopupMenuItem(
                        value: _PostMenu.report,
                        child: Text('Пожаловаться'),
                      ),
                    if (permissions.canHideAuthor)
                      const PopupMenuItem(
                        value: _PostMenu.hideAuthor,
                        child: Text('Скрыть публикации автора'),
                      ),
                    if (permissions.canBlockAuthor)
                      const PopupMenuItem(
                        value: _PostMenu.blockAuthor,
                        child: Text('Заблокировать автора'),
                      ),
                  ],
                ),
              ],
            ),
          ),
          _Body(post: post, full: full, onOpen: () => _openDetail(context)),
          if (post.isRoute) RoutePostPreview(routeId: post.routeId!),
          if (post.hasMedia) PostMedia(urls: post.mediaUrls),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => _like(context, ref),
                  tooltip: post.likedByMe ? 'Убрать отметку' : 'Нравится',
                  icon: Icon(
                    post.likedByMe ? Icons.favorite : Icons.favorite_border,
                    size: 20,
                    color: post.likedByMe
                        ? AppColors.primaryTint
                        : AppColors.textFaint,
                  ),
                ),
                Text('${post.likeCount}', style: theme.textTheme.bodyMedium),
                const SizedBox(width: 6),
                IconButton(
                  onPressed: onComment ?? () => _openDetail(context),
                  tooltip: 'Обсуждение',
                  icon: Icon(
                    Icons.mode_comment_outlined,
                    size: 19,
                    color: AppColors.textFaint,
                  ),
                ),
                Text('${post.commentCount}', style: theme.textTheme.bodyMedium),
                const Spacer(),
                IconButton(
                  onPressed: () => toggleSavePost(context, ref, post),
                  tooltip: isSaved ? 'Убрать из сохранённого' : 'Сохранить',
                  icon: Icon(
                    isSaved ? Icons.bookmark : Icons.bookmark_border,
                    size: 20,
                    color: isSaved ? AppColors.primaryTint : AppColors.textFaint,
                  ),
                ),
                IconButton(
                  onPressed: () => sharePost(context, post),
                  tooltip: 'Поделиться',
                  icon: Icon(Icons.ios_share, size: 19, color: AppColors.textFaint),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.post, required this.full, required this.onOpen});

  final Post post;
  final bool full;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final body = post.body?.trim() ?? '';
    final theme = Theme.of(context);

    // Статья в ленте — превью со ссылкой «Читать»: длинный текст ленту не
    // раздувает. На странице самого поста она раскрывается целиком.
    if (post.isArticle) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (post.title != null)
              GestureDetector(
                onTap: full ? null : onOpen,
                child: Text(post.title!, style: AppTypography.serif(full ? 30 : 24)),
              ),
            const SizedBox(height: 8),
            if (full)
              MarkdownView(data: body)
            else ...[
              Text(
                markdownPreview(body),
                style: theme.textTheme.bodyLarge,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: onOpen,
                child: Text(
                  'Читать статью',
                  style: TextStyle(
                    color: AppColors.primaryTint,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }

    if (body.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: post.bodyFormat == BodyFormat.markdown
          ? MarkdownView(data: body)
          : Text(body, style: theme.textTheme.bodyLarge),
    );
  }
}

String _relativeTime(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'только что';
  if (diff.inMinutes < 60) return '${diff.inMinutes} мин назад';
  if (diff.inHours < 24) return '${diff.inHours} ч назад';
  if (diff.inDays == 1) return 'вчера';
  return '${diff.inDays} дн назад';
}
