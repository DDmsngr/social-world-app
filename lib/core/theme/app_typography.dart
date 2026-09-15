import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Inter — весь интерфейс. Playfair Display — заголовки и акценты.
///
/// На сайте в заголовках стоит Instrument Serif, но у него нет кириллицы:
/// русский текст молча уезжает в системный запасной шрифт. Playfair Display
/// держит тот же высокий контраст и дисплейный характер, но с кириллицей.
abstract final class AppTypography {
  static TextStyle serif(
    double size, {
    Color color = AppColors.text,
    FontStyle style = FontStyle.normal,
    double height = 1.08,
  }) =>
      GoogleFonts.playfairDisplay(
        fontSize: size,
        color: color,
        fontStyle: style,
        height: height,
        letterSpacing: -0.012 * size,
        // По умолчанию Playfair рисует старостильные цифры: ноль выглядит
        // как строчная «о». В счётчиках и радиусах это читается как опечатка.
        fontFeatures: const [FontFeature.liningFigures()],
      );

  static TextTheme textTheme() {
    final inter = GoogleFonts.interTextTheme();
    return inter
        .apply(bodyColor: AppColors.text, displayColor: AppColors.text)
        .copyWith(
          displayLarge: serif(44),
          displayMedium: serif(36),
          headlineLarge: serif(30),
          headlineMedium: serif(24),
          titleLarge: GoogleFonts.inter(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
          bodyLarge: GoogleFonts.inter(
            fontSize: 15,
            height: 1.55,
            color: AppColors.text,
          ),
          bodyMedium: GoogleFonts.inter(
            fontSize: 14,
            height: 1.55,
            color: AppColors.textDim,
          ),
          labelSmall: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 2.2,
            color: AppColors.textFaint,
          ),
        );
  }
}
