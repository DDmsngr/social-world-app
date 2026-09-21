import 'package:flutter/material.dart';

import '../../domain/activity.dart';

/// Шкала тепловой карты Pulse: зелёный — низкая активность, жёлтый —
/// средняя, оранжевый — высокая, красный — очень высокая.
///
/// Цвета одинаковы в светлой и тёмной теме: это шкала измерения, а не
/// оформление, и «красный» должен читаться одинаково везде. Под тему
/// подстраивается только плотность заливки (см. [activityAlpha]).
abstract final class ActivityPalette {
  static const low = Color(0xFF3DA35D);
  static const medium = Color(0xFFE8C33C);
  static const high = Color(0xFFEF8A2B);
  static const peak = Color(0xFFD93A2B);

  /// «Спокойнее» — обратная сторона той же оценки, а не уровень активности,
  /// поэтому шкала к нему не применяется: приглушённый синий вместо неё.
  static const calm = Color(0xFF5B7FA6);

  static const _stops = <(double, Color)>[
    (0.00, low),
    (0.35, medium),
    (0.65, high),
    (1.00, peak),
  ];

  /// Цвет зоны по её нормированной оценке (0..1).
  static Color of(double intensity) {
    final value = intensity.clamp(0.0, 1.0).toDouble();
    for (var i = 0; i < _stops.length - 1; i++) {
      final (fromValue, fromColor) = _stops[i];
      final (toValue, toColor) = _stops[i + 1];
      if (value > toValue) continue;
      final span = toValue - fromValue;
      final t = span == 0 ? 0.0 : (value - fromValue) / span;
      return Color.lerp(fromColor, toColor, t)!;
    }
    return peak;
  }

  /// Цвет зоны с учётом режима карты.
  static Color forCell(double intensity, ActivityMode mode) =>
      mode == ActivityMode.calm ? calm : of(intensity);
}

/// Насколько плотно заливать зону. На тёмном фоне те же цвета выглядят
/// ярче, поэтому заливка слабее — иначе пятна забивают карту под собой.
double activityAlpha(double intensity, {required bool isDark}) {
  final base = isDark ? 0.10 : 0.13;
  final gain = isDark ? 0.20 : 0.26;
  return base + gain * intensity.clamp(0.0, 1.0);
}
