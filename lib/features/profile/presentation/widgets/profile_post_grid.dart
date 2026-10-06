import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/media/media_kind.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/text/markdown_preview.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/video_poster.dart';
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

/// Пост без фото: цветная плитка с началом текста. Цвет берётся из id поста,
/// поэтому у одного и того же поста он всегда один.
class _TextTile extends StatelessWidget {
  const _TextTile({required this.post});

  final Post post;

  static const _palettes = [
    [Color(0xFFEA2249), Color(0xFFFF7A59)],
    [Color(0xFF5B5BD6), Color(0xFF8E7CFF)],
    [Color(0xFF0E9F8E), Color(0xFF4ADE9C)],
    [Color(0xFFF59E0B), Color(0xFFFB7185)],
    [Color(0xFF2563EB), Color(0xFF22B8CF)],
    [Color(0xFF7C3AED), Color(0xFFEC4899)],
  ];

  @override
  Widget build(BuildContext context) {
    final raw = post.isArticle
        ? (post.title ?? markdownPreview(post.body ?? ''))
        : markdownPreview(post.body ?? '');
    final text = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    final colors = _palettes[post.id.hashCode.abs() % _palettes.length];
    // Чем короче текст, тем крупнее: короткая фраза должна читаться издалека.
    final size = text.length <= 24 ? 17.0 : (text.length <= 60 ? 14.0 : 12.0);

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Center(
          child: Text(
            text.isEmpty ? '·' : text,
            textAlign: TextAlign.center,
            maxLines: 6,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: size,
              height: 1.2,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              shadows: const [Shadow(blurRadius: 3, color: Color(0x33000000))],
            ),
          ),
        ),
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
    } else if (video && first.startsWith('http')) {
      content = VideoPoster(url: first, maxWidth: 360, showPlay: false);
    } else {
      content = _TextTile(post: post);
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
