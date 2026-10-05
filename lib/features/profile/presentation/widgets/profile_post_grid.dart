import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/media/media_kind.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/text/markdown_preview.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../feed/domain/entities/post.dart';

/// Публикации профиля сеткой в три колонки, как в привычных фотосетях.
/// Квадрат — первое фото; у видео и подборок значок в углу; пост без фото —
/// плитка с началом текста. Нажатие открывает публикацию целиком.
class ProfilePostGrid extends StatelessWidget {
  const ProfilePostGrid({super.key, required this.posts});

  final List<Post> posts;

  @override
  Widget build(BuildContext context) {
    return SliverGrid(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, index) => _Tile(post: posts[index]),
        childCount: posts.length,
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    final media = post.mediaUrls;
    final first = media.isEmpty ? null : media.first;
    final video = first != null && isVideoUrl(first);
    final photo = media.where((u) => !isVideoUrl(u)).firstOrNull;

    Widget content;
    if (photo != null && photo.startsWith('http')) {
      content = CachedNetworkImage(
        imageUrl: photo,
        fit: BoxFit.cover,
        memCacheWidth: 400,
        placeholder: (_, _) => ColoredBox(color: AppColors.ink2),
        errorWidget: (_, _, _) => ColoredBox(color: AppColors.ink2),
      );
    } else if (video) {
      content = ColoredBox(
        color: const Color(0xFF15151A),
        child: Center(
          child: Icon(Icons.play_circle_outline, color: Colors.white70, size: 36),
        ),
      );
    } else {
      final text = post.isArticle
          ? (post.title ?? markdownPreview(post.body ?? ''))
          : markdownPreview(post.body ?? '');
      content = ColoredBox(
        color: AppColors.card,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            text,
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              height: 1.25,
              fontWeight: post.isArticle ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      );
    }

    final badge = video
        ? Icons.videocam
        : media.length > 1
        ? Icons.collections
        : post.isArticle
        ? Icons.article_outlined
        : null;

    return GestureDetector(
      onTap: () => context.push('${Routes.posts}/${post.id}', extra: post),
      child: Stack(
        fit: StackFit.expand,
        children: [
          content,
          if (badge != null)
            Positioned(
              top: 6,
              right: 6,
              child: Icon(
                badge,
                size: 18,
                color: Colors.white,
                shadows: const [Shadow(blurRadius: 4, color: Colors.black54)],
              ),
            ),
        ],
      ),
    );
  }
}
