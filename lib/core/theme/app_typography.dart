import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Inter — весь интерфейс, включая заголовки.
///
/// Дизайнер рисует в SF Pro, но его лицензия Apple разрешает только
/// платформы Apple — в Android-сборку его класть нельзя. Inter — открытый
/// гротеск с кириллицей, по рисунку ближе всего к SF Pro. Заголовки по
/// макету жирные гротесковые (засечный Playfair Display убран 01.10.2026);
/// имя [serif] оставлено, чтобы не перетряхивать сотню экранов ради
/// переименования.
abstract final class AppTypography {
  static TextStyle serif(
    double size, {
    Color? color,
    FontStyle style = FontStyle.normal,
    double height = 1.15,
  }) =>
      GoogleFonts.inter(
        fontSize: size,
        color: color ?? AppColors.text,
        fontStyle: style,
        fontWeight: FontWeight.w700,
        height: height,
        letterSpacing: -0.02 * size,
      );

  static TextTheme textTheme(AppPalette p) {
    final inter = GoogleFonts.interTextTheme();
    return inter
        .apply(bodyColor: p.text, displayColor: p.text)
        .copyWith(
          displayLarge: serif(44, color: p.text),
          displayMedium: serif(36, color: p.text),
          headlineLarge: serif(30, color: p.text),
          headlineMedium: serif(24, color: p.text),
          titleLarge: GoogleFonts.inter(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: p.text,
          ),
          bodyLarge: GoogleFonts.inter(
            fontSize: 15,
            height: 1.55,
            color: p.text,
          ),
          bodyMedium: GoogleFonts.inter(
            fontSize: 14,
            height: 1.55,
            color: p.textDim,
          ),
          labelSmall: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 2.2,
            color: p.textFaint,
          ),
        );
  }
}
