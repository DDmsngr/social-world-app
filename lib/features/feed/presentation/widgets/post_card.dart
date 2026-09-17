import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../routes/presentation/widgets/route_post_preview.dart';
import '../../domain/entities/post.dart';

class PostCard extends StatelessWidget {
  const PostCard({
    super.key,
    required this.post,
    required this.onLike,
    required this.onReport,
  });

  final Post post;
  final VoidCallback onLike;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
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
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: AppColors.ink2,
                  backgroundImage: post.authorAvatarUrl == null
                      ? null
                      : CachedNetworkImageProvider(post.authorAvatarUrl!),
                  child: post.authorAvatarUrl != null
                      ? null
                      : Text(
                          post.authorName.characters.first.toUpperCase(),
                          style: AppTypography.serif(16, color: AppColors.primaryTint),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        post.authorName,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        [
                          _relativeTime(post.createdAt),
                          if (post.placeTitle != null) post.placeTitle!,
                        ].join(' · '),
                        style: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.copyWith(fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onReport,
                  tooltip: 'Пожаловаться',
                  icon: const Icon(
                    Icons.flag_outlined,
                    size: 19,
                    color: AppColors.textFaint,
                  ),
                ),
              ],
            ),
          ),
          if (post.body != null && post.body!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                post.body!,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          if (post.isRoute) RoutePostPreview(routeId: post.routeId!),
          if (post.hasMedia)
            AspectRatio(
              aspectRatio: 4 / 3,
              child: CachedNetworkImage(
                imageUrl: post.mediaUrls.first,
                fit: BoxFit.cover,
                placeholder: (_, _) => const ColoredBox(color: AppColors.ink2),
                errorWidget: (_, _, _) => const ColoredBox(
                  color: AppColors.ink2,
                  child: Center(
                    child: Icon(
                      Icons.image_not_supported_outlined,
                      color: AppColors.textFaint,
                    ),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 16, 6),
            child: Row(
              children: [
                IconButton(
                  onPressed: onLike,
                  tooltip: post.likedByMe ? 'Убрать отметку' : 'Нравится',
                  icon: Icon(
                    post.likedByMe ? Icons.favorite : Icons.favorite_border,
                    size: 20,
                    color: post.likedByMe
                        ? AppColors.primaryTint
                        : AppColors.textFaint,
                  ),
                ),
                Text(
                  '${post.likeCount}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
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
