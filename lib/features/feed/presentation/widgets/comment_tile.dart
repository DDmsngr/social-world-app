import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/media/photo_viewer.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../chat/presentation/widgets/emoji_panel.dart';
import '../../domain/entities/comment.dart';

/// Узел ветки: отступ по глубине, слева направляющая линия ветки — так же,
/// как это читается на Reddit.
class CommentTile extends StatelessWidget {
  const CommentTile({
    super.key,
    required this.comment,
    required this.hiddenReplies,
    required this.collapsed,
    required this.isMine,
    required this.onLike,
    required this.onDislike,
    required this.onReply,
    required this.onToggleCollapse,
    required this.onDelete,
  });

  final Comment comment;

  /// Сколько ответов спрятано под свёрнутой веткой — без этого числа непонятно,
  /// стоит ли её разворачивать.
  final int hiddenReplies;

  final bool collapsed;
  final bool isMine;
  final VoidCallback onLike;
  final VoidCallback onDislike;
  final VoidCallback onReply;
  final VoidCallback onToggleCollapse;
  final VoidCallback onDelete;

  /// Глубже шестого уровня отступ упирается в край экрана, поэтому
  /// визуальная лесенка на этом останавливается, а сама ветка продолжается.
  static const _maxIndentDepth = 6;
  static const _indentStep = 14.0;

  @override
  Widget build(BuildContext context) {
    final indent =
        (comment.depth > _maxIndentDepth ? _maxIndentDepth : comment.depth) *
        _indentStep;

    return Padding(
      padding: EdgeInsets.only(left: indent, bottom: 2),
      child: Container(
        decoration: BoxDecoration(
          border: comment.depth == 0
              ? null
              : Border(left: BorderSide(color: AppColors.hairStrong)),
        ),
        padding: EdgeInsets.only(left: comment.depth == 0 ? 0 : 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: onToggleCollapse,
              borderRadius: BorderRadius.circular(AppRadius.field),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    UserAvatar(
                      name: comment.authorName,
                      url: comment.authorAvatarUrl,
                      userId: comment.authorId,
                      radius: 11,
                    ),
                    const SizedBox(width: 8),
                    // Имя, как и аватар, ведёт в профиль; свернуть ветку можно
                    // остальной частью строки.
                    Flexible(
                      child: GestureDetector(
                        onTap: comment.deleted
                            ? onToggleCollapse
                            : () => openProfile(context, comment.authorId),
                        child: Text(
                          comment.authorName,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontSize: 13,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _relativeTime(comment.createdAt),
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textFaint,
                      ),
                    ),
                    if (collapsed && hiddenReplies > 0) ...[
                      const SizedBox(width: 8),
                      Text(
                        '+$hiddenReplies',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.primaryTint,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (!collapsed) ...[
              if (comment.deleted || (comment.body ?? '').isNotEmpty)
                Text(
                  comment.deleted ? 'Комментарий удалён' : comment.body ?? '',
                  style: comment.deleted
                      ? TextStyle(
                          color: AppColors.textFaint,
                          fontStyle: FontStyle.italic,
                        )
                      // 1–3 эмодзи без текста — крупно, как стикер в чате.
                      : switch (emojiOnlyCount(comment.body)) {
                          1 => const TextStyle(fontSize: 48, height: 1.1),
                          2 => const TextStyle(fontSize: 40, height: 1.1),
                          3 => const TextStyle(fontSize: 32, height: 1.1),
                          _ => Theme.of(context).textTheme.bodyLarge,
                        },
                ),
              // Картинки и гифки целиком: уменьшаются под ширину и высоту
              // ветки, но не обрезаются; тап открывает на весь экран.
              if (comment.hasMedia && !comment.deleted)
                for (var i = 0; i < comment.mediaUrls.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: GestureDetector(
                        onTap: () => showPhotoViewer(
                          context,
                          urls: comment.mediaUrls,
                          initialIndex: i,
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 260),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(AppRadius.field),
                            child: Image(
                              image: CachedNetworkImageProvider(comment.mediaUrls[i]),
                              fit: BoxFit.contain,
                              alignment: Alignment.centerLeft,
                              errorBuilder: (_, _, _) => Container(
                                width: 120,
                                height: 80,
                                color: AppColors.card,
                                child: Icon(Icons.broken_image_outlined, color: AppColors.textFaint),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              // Wrap, а не Row: у вложенных ответов кнопки не помещаются в
              // одну строку и раньше уезжали за край экрана.
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _Action(
                    icon: comment.likedByMe
                        ? Icons.favorite
                        : Icons.favorite_border,
                    label: '${comment.likeCount}',
                    color: comment.likedByMe
                        ? AppColors.primaryTint
                        : AppColors.textFaint,
                    onTap: comment.deleted ? null : onLike,
                  ),
                  _Action(
                    icon: comment.dislikedByMe
                        ? Icons.thumb_down
                        : Icons.thumb_down_outlined,
                    label: '${comment.dislikeCount}',
                    color: comment.dislikedByMe
                        ? AppColors.textDim
                        : AppColors.textFaint,
                    onTap: comment.deleted ? null : onDislike,
                  ),
                  _Action(
                    icon: Icons.reply,
                    label: 'Ответить',
                    color: AppColors.textFaint,
                    onTap: onReply,
                  ),
                  if (isMine && !comment.deleted)
                    _Action(
                      icon: Icons.delete_outline,
                      label: 'Удалить',
                      color: AppColors.textFaint,
                      onTap: onDelete,
                    ),
                  // Свернуть ветку явной кнопкой: раньше это было только
                  // тапом по шапке, и про него никто не знал.
                  _Action(
                    icon: Icons.unfold_less,
                    label: 'Свернуть',
                    color: AppColors.textFaint,
                    onTap: onToggleCollapse,
                  ),
                ],
              ),
            ] else
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: TextButton.icon(
                  onPressed: onToggleCollapse,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 30),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.unfold_more, size: 16),
                  label: Text(
                    hiddenReplies > 0
                        ? 'Развернуть · ещё $hiddenReplies'
                        : 'Развернуть',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 34),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: color,
      ),
      icon: Icon(icon, size: 16, color: color),
      label: Text(label, style: TextStyle(fontSize: 12, color: color)),
    );
  }
}

String _relativeTime(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'только что';
  if (diff.inMinutes < 60) return '${diff.inMinutes} мин';
  if (diff.inHours < 24) return '${diff.inHours} ч';
  if (diff.inDays == 1) return 'вчера';
  return '${diff.inDays} дн';
}
