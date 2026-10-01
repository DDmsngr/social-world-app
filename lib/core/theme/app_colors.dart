import 'package:flutter/material.dart';

/// Набор цветов одной темы.
///
/// Пропорция та же в обеих темах: фон держит ~80% экрана, текст ~15%,
/// акцент ~5%. Акцент — цвет действия: активная кнопка, выбранная вкладка,
/// включённый элемент. Фоном карточек он не бывает.
@immutable
class AppPalette {
  const AppPalette({
    required this.brightness,
    required this.ink,
    required this.ink2,
    required this.card,
    required this.paper,
    required this.primary,
    required this.primaryHover,
    required this.primaryTint,
    required this.onPrimary,
    required this.success,
    required this.danger,
    required this.geo,
    required this.champagne,
    required this.text,
    required this.textDim,
    required this.textFaint,
    required this.hair,
    required this.hairStrong,
    required this.bubbleMine,
    required this.onBubbleMine,
  });

  final Brightness brightness;

  /// Фон экрана.
  final Color ink;

  /// Листы, нижняя навигация, плавающие плашки на карте.
  final Color ink2;
  final Color card;

  /// Светлые значки и точки поверх фото — светлые в обеих темах.
  final Color paper;

  /// Заливка кнопки действия.
  final Color primary;

  /// Нажатие/фокус: заметно отличается от [primary].
  final Color primaryHover;

  /// Акцент для текста, иконок и тонких линий на фоне [ink]/[card].
  final Color primaryTint;

  /// Всё, что лежит поверх [primary].
  final Color onPrimary;

  final Color success;
  final Color danger;

  /// Гео и карта — отдельная холодная ветка, иначе метки сливаются с кнопками.
  final Color geo;

  /// Выбранное состояние там, где акцент-розовый не подходит: активная
  /// вкладка нижней навигации, выбранный сегмент SegmentedButton. Из
  /// референса — розовый там читается как «действие», а не «выбрано».
  final Color champagne;

  final Color text;
  final Color textDim;
  final Color textFaint;

  final Color hair;
  final Color hairStrong;

  /// Свой пузырь в чате. Нейтральный, а не [primary]: переписка — это
  /// длинное чтение, и сплошной акцент на половине экрана утомляет и
  /// спорит с кнопками действия.
  final Color bubbleMine;
  final Color onBubbleMine;

  bool get isDark => brightness == Brightness.dark;

  /// Тёмная тема по макетам дизайнера (Figma, 01.10.2026): графитовый фон
  /// #1C1C1C, карточки #323233, белый текст и один акцент — вишнёво-красный
  /// #D83D5F, только для действий. Бордово-платиновая палитра отменена.
  static const designerDark = AppPalette(
    brightness: Brightness.dark,
    ink: Color(0xFF1C1C1C),
    ink2: Color(0xFF2A2A2B),
    card: Color(0xFF323233),
    paper: Color(0xFFFFFFFF),
    primary: Color(0xFFD83D5F),
    primaryHover: Color(0xFFE5587A),
    // Акцент для текста и иконок на тёмном: чуть светлее заливки кнопки,
    // иначе #D83D5F на #1C1C1C читается хуже 4:1.
    primaryTint: Color(0xFFEC5C7C),
    onPrimary: Color(0xFF000000),
    success: Color(0xFF4CC38A),
    danger: Color(0xFFFF4D4D),
    geo: Color(0xFF4F9DDE),
    // Выбранное состояние (вкладки, сегменты): белый, не розовый — розовый
    // у макета только у кнопок действия.
    champagne: Color(0xFFFFFFFF),
    text: Color(0xFFFFFFFF),
    textDim: Color(0xFFB5B5B8),
    textFaint: Color(0x99B5B5B8),
    hair: Color(0x33FFFFFF),
    hairStrong: Color(0xFF48484A),
    bubbleMine: Color(0xFF3A3A3C),
    onBubbleMine: Color(0xFFFFFFFF),
  );

  /// Светлая тема по макетам дизайнера: тёплый белый #F8F5F2, карточки
  /// #EBEBEB, чёрный текст, тот же акцент #D83D5F.
  static const designerLight = AppPalette(
    brightness: Brightness.light,
    ink: Color(0xFFF8F5F2),
    ink2: Color(0xFFFFFFFF),
    card: Color(0xFFEBEBEB),
    paper: Color(0xFFFFFFFF),
    primary: Color(0xFFD83D5F),
    primaryHover: Color(0xFFC8284C),
    primaryTint: Color(0xFFC9304F),
    onPrimary: Color(0xFF000000),
    success: Color(0xFF2E8B5E),
    danger: Color(0xFFEC3030),
    geo: Color(0xFF2F7ACB),
    champagne: Color(0xFF1C1C1C),
    text: Color(0xFF000000),
    textDim: Color(0xFF5E5E62),
    textFaint: Color(0x995E5E62),
    hair: Color(0x33000000),
    hairStrong: Color(0xFFD1D1D6),
    bubbleMine: Color(0xFFE2E2E4),
    onBubbleMine: Color(0xFF000000),
  );}

/// Цвета текущей темы.
///
/// Геттеры, а не контекст: экраны читают цвет в build(), а при смене темы
/// app.dart подменяет [current] и один раз пересобирает всё дерево
/// (см. `rebuildWholeTree`), сохраняя стек навигации и состояние экранов.
abstract final class AppColors {
  static AppPalette current = AppPalette.designerDark;

  static Color get ink => current.ink;
  static Color get ink2 => current.ink2;
  static Color get card => current.card;
  static Color get paper => current.paper;
  static Color get primary => current.primary;
  static Color get primaryHover => current.primaryHover;
  static Color get primaryTint => current.primaryTint;
  static Color get onPrimary => current.onPrimary;
  static Color get success => current.success;
  static Color get danger => current.danger;
  static Color get geo => current.geo;
  static Color get champagne => current.champagne;
  static Color get text => current.text;
  static Color get textDim => current.textDim;
  static Color get textFaint => current.textFaint;
  static Color get hair => current.hair;
  static Color get hairStrong => current.hairStrong;
  static Color get bubbleMine => current.bubbleMine;
  static Color get onBubbleMine => current.onBubbleMine;
}
