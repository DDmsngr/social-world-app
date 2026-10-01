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

  /// Тёмная тема по борду дизайнера (Figma, экраны «Событие · Dark» и
  /// «Диалог · Dark»): почти чёрный фон, панели и пузыри — ступени графита,
  /// белый текст и один акцент — красный #EA2249 для действий, прочитанных
  /// сообщений, цитат и счётчиков. Бордово-платиновая палитра отменена.
  static const designerDark = AppPalette(
    brightness: Brightness.dark,
    ink: Color(0xFF0E0F10),
    ink2: Color(0xFF191A1C),
    card: Color(0xFF242526),
    paper: Color(0xFFFFFFFF),
    primary: Color(0xFFEA2249),
    primaryHover: Color(0xFFF03E5F),
    // Акцент для текста и иконок на тёмном фоне — светлее заливки кнопки:
    // #EA2249 на почти чёрном мелким текстом читается хуже.
    primaryTint: Color(0xFFF03E5F),
    onPrimary: Color(0xFFFFFFFF),
    success: Color(0xFF4CC38A),
    danger: Color(0xFFFF4D4D),
    geo: Color(0xFF4F9DDE),
    // Выбранное состояние (вкладки, сегменты): белый, не красный — красный
    // у макета означает действие.
    champagne: Color(0xFFFFFFFF),
    text: Color(0xFFFFFFFF),
    textDim: Color(0xFFA9AAAE),
    textFaint: Color(0x99A9AAAE),
    hair: Color(0x1FFFFFFF),
    hairStrong: Color(0xFF3A3B3D),
    bubbleMine: Color(0xFF2C2D2F),
    onBubbleMine: Color(0xFFFFFFFF),
  );

  /// Светлая тема по тому же борду: белый фон, светло-серые карточки и
  /// пузыри, чёрный текст, тот же красный акцент.
  static const designerLight = AppPalette(
    brightness: Brightness.light,
    ink: Color(0xFFFFFFFF),
    ink2: Color(0xFFF7F7F9),
    card: Color(0xFFF2F3F5),
    paper: Color(0xFFFFFFFF),
    primary: Color(0xFFEA2249),
    primaryHover: Color(0xFFD01A3E),
    primaryTint: Color(0xFFD81E45),
    onPrimary: Color(0xFFFFFFFF),
    success: Color(0xFF2E8B5E),
    danger: Color(0xFFEC3030),
    geo: Color(0xFF2F7ACB),
    champagne: Color(0xFF111111),
    text: Color(0xFF111111),
    textDim: Color(0xFF6B6C70),
    textFaint: Color(0x996B6C70),
    hair: Color(0x1A000000),
    hairStrong: Color(0xFFDADBDF),
    bubbleMine: Color(0xFFE9EAEF),
    onBubbleMine: Color(0xFF111111),
  );
}

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
