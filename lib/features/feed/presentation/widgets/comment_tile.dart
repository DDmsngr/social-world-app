import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
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
              : const Border(left: BorderSide(color: AppColors.hairStrong)),
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
                    CircleAvatar(
                      radius: 11,
                      backgroundColor: AppColors.ink2,
                      backgroundImage: comment.authorAvatarUrl == null
                          ? null
                          : CachedNetworkImageProvider(comment.authorAvatarUrl!),
                      child: comment.authorAvatarUrl != null
                          ? null
                          : Text(
                              comment.authorName.characters.first.toUpperCase(),
                              style: AppTypography.serif(
                                11,
                                color: AppColors.primaryTint,
                              ),
                            ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        comment.authorName,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontSize: 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _relativeTime(comment.createdAt),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textFaint,
                      ),
                    ),
                    if (collapsed && hiddenReplies > 0) ...[
                      const SizedBox(width: 8),
                      Text(
                        '+$hiddenReplies',
                        style: const TextStyle(
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
              Text(
                comment.deleted ? 'Комментарий удалён' : comment.body ?? '',
                style: comment.deleted
                    ? const TextStyle(
                        color: AppColors.textFaint,
                        fontStyle: FontStyle.italic,
                      )
                    : Theme.of(context).textTheme.bodyLarge,
              ),
              // Фото и гифки в комментариях появятся позже — разбор и показ
              // уже готовы, кнопки прикрепления ещё нет.
              if (comment.hasMedia)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.field),
                    child: CachedNetworkImage(
                      imageUrl: comment.mediaUrls.first,
                      height: 160,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              Row(
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
                ],
              ),
            ],
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
