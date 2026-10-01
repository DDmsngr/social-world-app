import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Стеклянная плашка из макета («Liquid Glass — Regular»): размытие фона,
/// полупрозрачная заливка, тонкая светлая обводка и мягкая тень.
///
/// Значения сняты с файла Figma: заливка #F5F5F7 при 60%, тень 50 px при 30%
/// чёрного, радиус 28. Настоящего преломления нет — это дорого на слабых
/// Android, а [blur] можно выставить в 0, и плашка останется просто
/// полупрозрачной (запасной вид без `BackdropFilter`).
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.radius = 28,
    this.blur = 24,
    this.padding,
    this.fill,
    this.shadow = true,
  });

  final Widget child;
  final double radius;

  /// Радиус размытия того, что под плашкой. 0 — без размытия.
  final double blur;
  final EdgeInsetsGeometry? padding;

  /// Цвет заливки; по умолчанию светлый стеклянный в светлой теме и тёмный в
  /// тёмной.
  final Color? fill;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.current.isDark;
    final borderRadius = BorderRadius.circular(radius);
    final body = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        color: fill ??
            (dark
                ? const Color(0x99303034)
                : const Color(0x99F5F5F7)),
        border: Border.all(
          color: dark ? const Color(0x33FFFFFF) : const Color(0x80FFFFFF),
        ),
      ),
      child: padding == null ? child : Padding(padding: padding!, child: child),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: shadow
            ? const [BoxShadow(color: Color(0x4D000000), blurRadius: 50)]
            : null,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: blur > 0
            ? BackdropFilter(
                filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                child: body,
              )
            : body,
      ),
    );
  }
}
