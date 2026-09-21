import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'app_typography.dart';

abstract final class AppRadius {
  static const card = 20.0;
  static const chip = 999.0;
  static const field = 14.0;
}

abstract final class AppSpacing {
  static const gutter = 20.0;
  static const section = 32.0;

  /// Отступы прокручиваемого экрана вне нижней навигации. Низ считается от
  /// системной панели устройства (жесты или три кнопки), а не фиксированным
  /// числом: иначе последняя кнопка уезжает под системные клавиши.
  static EdgeInsets page(BuildContext context, {double top = 12}) =>
      EdgeInsets.fromLTRB(
        gutter,
        top,
        gutter,
        24 + MediaQuery.paddingOf(context).bottom,
      );
}

abstract final class AppTheme {
  /// Системные панели рисуются поверх приложения без собственной подложки:
  /// строка состояния и навигационная панель прозрачные, а иконки подбираются
  /// под тему. `systemNavigationBarContrastEnforced: false` убирает
  /// полупрозрачную «плашку» Android под тремя кнопками — из-за неё казалось,
  /// что кнопки лежат в отдельных светящихся прямоугольниках.
  static SystemUiOverlayStyle overlayStyle(AppPalette p) => SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: p.isDark ? Brightness.light : Brightness.dark,
    statusBarBrightness: p.isDark ? Brightness.dark : Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness:
        p.isDark ? Brightness.light : Brightness.dark,
    systemNavigationBarContrastEnforced: false,
  );

  static ThemeData build(AppPalette p) {
    final base = p.isDark
        ? ThemeData.dark(useMaterial3: true)
        : ThemeData.light(useMaterial3: true);

    final scheme = p.isDark
        ? ColorScheme.dark(
            primary: p.primary,
            onPrimary: p.onPrimary,
            secondary: p.success,
            surface: p.ink2,
            onSurface: p.text,
            error: p.danger,
          )
        : ColorScheme.light(
            primary: p.primary,
            onPrimary: p.onPrimary,
            secondary: p.success,
            surface: p.ink2,
            onSurface: p.text,
            error: p.danger,
          );

    return base.copyWith(
      scaffoldBackgroundColor: p.ink,
      canvasColor: p.ink,
      colorScheme: scheme,
      textTheme: AppTypography.textTheme(p),
      iconTheme: IconThemeData(color: p.text),
      dividerTheme: DividerThemeData(color: p.hair, thickness: 1, space: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: p.ink,
        foregroundColor: p.text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: AppTypography.serif(24, color: p.text),
        systemOverlayStyle: overlayStyle(p),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.primary,
          foregroundColor: p.onPrimary,
          disabledBackgroundColor: p.card,
          disabledForegroundColor: p.textFaint,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.chip),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ).copyWith(
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed) ||
                states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused)) {
              return p.primaryHover;
            }
            return null;
          }),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: p.textDim),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.card,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        hintStyle: TextStyle(color: p.textFaint),
        prefixIconColor: p.textDim,
        suffixIconColor: p.textDim,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.field),
          borderSide: BorderSide(color: p.hair),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.field),
          borderSide: BorderSide(color: p.hair),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.field),
          borderSide: BorderSide(color: p.primaryTint),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.ink2,
        surfaceTintColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11,
            letterSpacing: 0.4,
            color: states.contains(WidgetState.selected)
                ? p.primaryTint
                : p.textFaint,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 24,
            color: states.contains(WidgetState.selected)
                ? p.primaryTint
                : p.textFaint,
          ),
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? p.primaryTint
              : p.textFaint,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.ink2,
        contentTextStyle: TextStyle(color: p.text),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
