import 'dart:math' as math;

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
  const ProfilePostGrid({super.key, required this.posts, this.showVisibility = false});

  final List<Post> posts;

  /// Подписи «только мне» и «подписчикам» нужны автору, чужому они ни к чему:
  /// он видит пост, значит, ему он и предназначен.
  final bool showVisibility;

  @override
  Widget build(BuildContext context) {
    return SliverGrid(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, index) => _Tile(post: posts[index], showVisibility: showVisibility),
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Слово не должно рваться посреди: шрифт подбирается под самое
          // длинное слово (жирная кириллица ≈ 0,62 кегля на букву).
          final longest = text.split(' ').fold<int>(1, (m, w) => w.length > m ? w.length : m);
          final fit = (constraints.maxWidth - 20) / (longest * 0.62);
          final fontSize = fit < size ? fit.clamp(9.0, size) : size;
          return Padding(
            padding: const EdgeInsets.all(10),
            child: Center(
              child: Text(
                text.isEmpty ? '·' : text,
                textAlign: TextAlign.center,
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: fontSize,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  shadows: const [Shadow(blurRadius: 3, color: Color(0x33000000))],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Маршрут в сетке: тёмная плитка со значком пути и названием, чтобы его
/// нельзя было принять за текстовый пост.
class _RouteTile extends StatelessWidget {
  const _RouteTile({required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    final title = (post.body ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
    return Stack(
      fit: StackFit.expand,
      children: [
        // Нарисованный «образ карты»: у каждого маршрута свой из пяти вариантов.
        CustomPaint(
          painter: MapArtPainter(
            variant: post.id.hashCode.abs() % 5,
            street: AppColors.textDim,
            accent: AppColors.primaryTint,
            base: AppColors.ink2,
          ),
        ),
        // Затемнение под текстом, чтобы читался на любой «карте».
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x33000000), Color(0xB3000000)],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                'МАРШРУТ',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 0.8,
                  color: AppColors.primaryTint,
                ),
              ),
              if (title.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Условный «план города»: улицы, кварталы, река и линия маршрута. Один и
/// тот же вариант всегда рисуется одинаково (генератор с зерном).
class MapArtPainter extends CustomPainter {
  const MapArtPainter({
    required this.variant,
    required this.street,
    required this.accent,
    required this.base,
  });

  final int variant;
  final Color street;
  final Color accent;
  final Color base;

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(variant * 7919 + 13);
    final w = size.width;
    final h = size.height;
    // Улицы и река уходят за края плитки: без обрезки они рисовались по всему экрану.
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, Paint()..color = base);

    // Кварталы.
    final block = Paint()..color = street.withValues(alpha: 0.07);
    for (var i = 0; i < 9; i++) {
      final bw = w * (0.12 + rnd.nextDouble() * 0.2);
      final bh = h * (0.1 + rnd.nextDouble() * 0.2);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(rnd.nextDouble() * (w - bw), rnd.nextDouble() * (h - bh), bw, bh),
          const Radius.circular(3),
        ),
        block,
      );
    }

    // Река.
    final river = Path()
      ..moveTo(-10, h * (0.2 + rnd.nextDouble() * 0.6))
      ..cubicTo(
        w * 0.3, h * rnd.nextDouble(),
        w * 0.6, h * rnd.nextDouble(),
        w + 10, h * (0.2 + rnd.nextDouble() * 0.6),
      );
    canvas.drawPath(
      river,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.07
        ..color = const Color(0xFF5B8DEF).withValues(alpha: 0.16),
    );

    // Улицы: две семьи линий под прямым углом и пара магистралей.
    final angle = rnd.nextDouble() * math.pi;
    final thin = Paint()
      ..strokeWidth = 1
      ..color = street.withValues(alpha: 0.16);
    final main = Paint()
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..color = street.withValues(alpha: 0.28);
    final center = Offset(w / 2, h / 2);
    final reach = w + h;
    for (var family = 0; family < 2; family++) {
      final a = angle + family * math.pi / 2;
      final dir = Offset(math.cos(a), math.sin(a));
      final normal = Offset(-dir.dy, dir.dx);
      for (var i = -6; i <= 6; i++) {
        final shift = normal * (i * (w * 0.16) + rnd.nextDouble() * 6);
        canvas.drawLine(center + shift - dir * reach, center + shift + dir * reach, i % 4 == 0 ? main : thin);
      }
    }

    // Маршрут: плавная линия из угла в угол с отметками начала и конца.
    final start = Offset(w * (0.12 + rnd.nextDouble() * 0.2), h * (0.65 + rnd.nextDouble() * 0.25));
    final end = Offset(w * (0.68 + rnd.nextDouble() * 0.2), h * (0.1 + rnd.nextDouble() * 0.25));
    final route = Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(
        w * rnd.nextDouble(), h * (0.3 + rnd.nextDouble() * 0.5),
        w * rnd.nextDouble(), h * (0.2 + rnd.nextDouble() * 0.5),
        end.dx, end.dy,
      );
    canvas.drawPath(
      route,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2
        ..strokeCap = StrokeCap.round
        ..color = accent.withValues(alpha: 0.95),
    );
    canvas.drawCircle(start, 4.5, Paint()..color = Colors.white);
    canvas.drawCircle(end, 4.5, Paint()..color = accent);
  }

  @override
  bool shouldRepaint(MapArtPainter old) =>
      old.variant != variant || old.street != street || old.accent != accent || old.base != base;
}

class _Tile extends StatelessWidget {
  const _Tile({required this.post, required this.showVisibility});

  final Post post;
  final bool showVisibility;

  @override
  Widget build(BuildContext context) {
    final media = post.mediaUrls;
    final first = media.isEmpty ? null : media.first;
    final video = first != null && isVideoUrl(first);
    final photo = media.where((u) => !isVideoUrl(u)).firstOrNull;

    Widget content;
    if (post.isRoute) {
      content = _RouteTile(post: post);
    } else if (photo != null && photo.startsWith('http')) {
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

    final badge = post.isRoute
        ? Icons.route
        : video
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
          // Кому виден пост: «только мне» — замок, «подписчикам» — люди.
          // Публичные без значка. Чужие закрытые посты сюда и не приходят.
          if (showVisibility && post.visibility != PostVisibility.everyone)
            Positioned(
              left: 6,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      post.visibility == PostVisibility.onlyMe
                          ? Icons.lock_outline
                          : Icons.group_outlined,
                      size: 13,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      post.visibility == PostVisibility.onlyMe ? 'только мне' : 'подписчикам',
                      style: const TextStyle(color: Colors.white, fontSize: 10.5),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
