import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/features/discover/domain/activity.dart';
import 'package:social_world/features/discover/presentation/widgets/activity_palette.dart';

void main() {
  test('шкала идёт от зелёного к красному, а не наоборот', () {
    expect(ActivityPalette.of(0), ActivityPalette.low);
    expect(ActivityPalette.of(1), ActivityPalette.peak);

    // Отдельные каналы не монотонны: оранжевый ярче красного по красному
    // каналу. Растёт «теплота» — насколько красного больше, чем зелёного.
    double warmth(double intensity) {
      final color = ActivityPalette.of(intensity);
      return color.r - color.g;
    }

    var previous = warmth(0);
    for (var i = 1; i <= 10; i++) {
      final current = warmth(i / 10);
      expect(
        current,
        greaterThan(previous),
        reason: 'зона с активностью ${i / 10} должна быть теплее предыдущей',
      );
      previous = current;
    }
  });

  test('значения вне 0..1 не ломают шкалу', () {
    expect(ActivityPalette.of(-5), ActivityPalette.low);
    expect(ActivityPalette.of(42), ActivityPalette.peak);
  });

  test('«спокойнее» шкалой активности не красится', () {
    expect(
      ActivityPalette.forCell(0.9, ActivityMode.calm),
      ActivityPalette.calm,
    );
    expect(
      ActivityPalette.forCell(0.9, ActivityMode.lively),
      isNot(ActivityPalette.calm),
    );
  });

  test('на тёмной теме заливка слабее, но растёт с активностью', () {
    expect(
      activityAlpha(0.5, isDark: true),
      lessThan(activityAlpha(0.5, isDark: false)),
    );
    expect(
      activityAlpha(0.1, isDark: false),
      lessThan(activityAlpha(0.9, isDark: false)),
    );
  });
}
