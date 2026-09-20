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
    required this.text,
    required this.textDim,
    required this.textFaint,
    required this.hair,
    required this.hairStrong,
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

  final Color text;
  final Color textDim;
  final Color textFaint;

  final Color hair;
  final Color hairStrong;

  bool get isDark => brightness == Brightness.dark;

  /// «Бургунди и шампань» — тёмная тема по выбору Левона. Все шесть кодов —
  /// один в один из присланного референса (Фон/Карточки/Вторичный фон/
  /// Акцент/Текст/Вторичный текст), кроме [primaryHover] — его в референсе
  /// нет, это состояние нажатия, придуманное поверх акцента.
  static const burgundyChampagne = AppPalette(
    brightness: Brightness.dark,
    ink: Color(0xFF21151D),
    ink2: Color(0xFF3B2731),
    card: Color(0xFF302029),
    paper: Color(0xFFFFF8F0),
    primary: Color(0xFFE89BBA),
    primaryHover: Color(0xFFF2B8CE),
    primaryTint: Color(0xFFE89BBA),
    onPrimary: Color(0xFF21151D),
    success: Color(0xFF62C08F),
    danger: Color(0xFFE8737D),
    geo: Color(0xFF82AED6),
    text: Color(0xFFFFF8F0),
    textDim: Color(0xFFBBA9AF),
    textFaint: Color(0x99BBA9AF),
    hair: Color(0x804A3440),
    hairStrong: Color(0xFF4A3440),
  );

  /// «Тёплый песок» — светлая тема. Коды сняты со скриншота макета, их
  /// заменят точные значения, когда придут от Левона.
  static const warmSand = AppPalette(
    brightness: Brightness.light,
    ink: Color(0xFFFBF3EA),
    ink2: Color(0xFFFFFFFF),
    card: Color(0xFFFFFFFF),
    paper: Color(0xFFFFFFFF),
    primary: Color(0xFFB94E36),
    primaryHover: Color(0xFFC8573D),
    primaryTint: Color(0xFFB04A33),
    onPrimary: Color(0xFFFFFFFF),
    success: Color(0xFF2E8B5E),
    danger: Color(0xFFC2414B),
    geo: Color(0xFF3C74A8),
    text: Color(0xFF3A2A24),
    textDim: Color(0xFF7A635A),
    textFaint: Color(0x997A635A),
    hair: Color(0x80E3D2C3),
    hairStrong: Color(0xFFDCC6B4),
  );
}

/// Цвета текущей темы.
///
/// Геттеры, а не контекст: экраны читают цвет в build(), а при смене темы
/// app.dart подменяет [current] и один раз пересобирает всё дерево
/// (см. `rebuildWholeTree`), сохраняя стек навигации и состояние экранов.
abstract final class AppColors {
  static AppPalette current = AppPalette.burgundyChampagne;

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
  static Color get text => current.text;
  static Color get textDim => current.textDim;
  static Color get textFaint => current.textFaint;
  static Color get hair => current.hair;
  static Color get hairStrong => current.hairStrong;
}
