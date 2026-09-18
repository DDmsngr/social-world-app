import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_colors.dart';

enum ThemeChoice {
  system('Как в системе', 'Следует настройке телефона'),
  dark('Тёмная', null),
  light('Светлая', null),
  schedule('По времени суток', 'Тёмная с 20:00 до 7:00');

  const ThemeChoice(this.label, this.hint);

  final String label;
  final String? hint;

  static ThemeChoice parse(String? raw) => ThemeChoice.values.firstWhere(
    (choice) => choice.name == raw,
    orElse: () => ThemeChoice.system,
  );
}

const _prefsKey = 'theme_choice';

/// Сохранённый выбор, прочитанный в main() до первого кадра — иначе при
/// запуске на секунду мелькает тема по умолчанию.
final initialThemeChoiceProvider = Provider<ThemeChoice>(
  (_) => ThemeChoice.system,
);

Future<ThemeChoice> loadThemeChoice() async {
  final prefs = await SharedPreferences.getInstance();
  return ThemeChoice.parse(prefs.getString(_prefsKey));
}

class ThemeChoiceController extends Notifier<ThemeChoice> {
  @override
  ThemeChoice build() {
    ref.keepAlive();
    return ref.read(initialThemeChoiceProvider);
  }

  Future<void> choose(ThemeChoice choice) async {
    state = choice;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, choice.name);
  }
}

final themeChoiceProvider = NotifierProvider<ThemeChoiceController, ThemeChoice>(
  ThemeChoiceController.new,
);

const _darkFromHour = 20;
const _lightFromHour = 7;

bool _isNight(DateTime now) =>
    now.hour >= _darkFromHour || now.hour < _lightFromHour;

AppPalette resolvePalette(
  ThemeChoice choice, {
  required Brightness platformBrightness,
  required DateTime now,
}) {
  final dark = switch (choice) {
    ThemeChoice.system => platformBrightness == Brightness.dark,
    ThemeChoice.dark => true,
    ThemeChoice.light => false,
    ThemeChoice.schedule => _isNight(now),
  };
  return dark ? AppPalette.burgundyChampagne : AppPalette.warmSand;
}

/// Ближайший момент, когда режим «по времени суток» переключит тему.
DateTime nextScheduleSwitch(DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final candidates = [
    today.add(const Duration(hours: _lightFromHour)),
    today.add(const Duration(hours: _darkFromHour)),
    today.add(const Duration(days: 1, hours: _lightFromHour)),
  ];
  return candidates.firstWhere((moment) => moment.isAfter(now));
}

/// Пересобирает всё поддерево [context]: экраны читают [AppColors] в
/// build(), и без этого после смены темы остались бы в старых цветах.
/// Состояние (стек навигации, прокрутка, введённый текст) не теряется —
/// элементы помечаются грязными, а не пересоздаются.
void rebuildWholeTree(BuildContext context) {
  void mark(Element element) {
    element.markNeedsBuild();
    element.visitChildren(mark);
  }

  (context as Element).visitChildren(mark);
}
