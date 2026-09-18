import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/core/theme/app_colors.dart';
import 'package:social_world/core/theme/theme_choice.dart';

class _Swatch extends StatelessWidget {
  const _Swatch();

  @override
  Widget build(BuildContext context) =>
      ColoredBox(color: AppColors.ink, child: const SizedBox(width: 8));
}

class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  var taps = 0;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () => setState(() => taps++),
    child: Text('$taps', style: TextStyle(color: AppColors.text)),
  );
}

Color _swatchColor(WidgetTester tester) => tester
    .widget<ColoredBox>(
      find.descendant(of: find.byType(_Swatch), matching: find.byType(ColoredBox)),
    )
    .color;

void main() {
  tearDown(() => AppColors.current = AppPalette.burgundyChampagne);

  group('resolvePalette', () {
    final noon = DateTime(2026, 9, 18, 12);
    final night = DateTime(2026, 9, 18, 23);

    test('«как в системе» следует теме телефона', () {
      expect(
        resolvePalette(
          ThemeChoice.system,
          platformBrightness: Brightness.dark,
          now: noon,
        ),
        same(AppPalette.burgundyChampagne),
      );
      expect(
        resolvePalette(
          ThemeChoice.system,
          platformBrightness: Brightness.light,
          now: night,
        ),
        same(AppPalette.warmSand),
      );
    });

    test('явный выбор не зависит ни от телефона, ни от часов', () {
      expect(
        resolvePalette(
          ThemeChoice.light,
          platformBrightness: Brightness.dark,
          now: night,
        ),
        same(AppPalette.warmSand),
      );
      expect(
        resolvePalette(
          ThemeChoice.dark,
          platformBrightness: Brightness.light,
          now: noon,
        ),
        same(AppPalette.burgundyChampagne),
      );
    });

    test('по времени суток: тёмная с 20:00 до 7:00', () {
      AppPalette at(int hour, [int minute = 0]) => resolvePalette(
        ThemeChoice.schedule,
        platformBrightness: Brightness.light,
        now: DateTime(2026, 9, 18, hour, minute),
      );

      expect(at(6, 59), same(AppPalette.burgundyChampagne));
      expect(at(7), same(AppPalette.warmSand));
      expect(at(19, 59), same(AppPalette.warmSand));
      expect(at(20), same(AppPalette.burgundyChampagne));
      expect(at(0), same(AppPalette.burgundyChampagne));
    });
  });

  test('следующее переключение расписания — ближайшая из 7:00 и 20:00', () {
    expect(
      nextScheduleSwitch(DateTime(2026, 9, 18, 3)),
      DateTime(2026, 9, 18, 7),
    );
    expect(
      nextScheduleSwitch(DateTime(2026, 9, 18, 7)),
      DateTime(2026, 9, 18, 20),
    );
    expect(
      nextScheduleSwitch(DateTime(2026, 9, 18, 21)),
      DateTime(2026, 9, 19, 7),
    );
  });

  test('неизвестное сохранённое значение даёт «как в системе»', () {
    expect(ThemeChoice.parse(null), ThemeChoice.system);
    expect(ThemeChoice.parse('purple'), ThemeChoice.system);
    expect(ThemeChoice.parse('schedule'), ThemeChoice.schedule);
  });

  testWidgets(
    'смена темы перекрашивает даже const-виджеты и не теряет их состояние',
    (tester) async {
      AppColors.current = AppPalette.burgundyChampagne;
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Column(children: [_Swatch(), _Counter()])),
        ),
      );
      await tester.tap(find.byType(TextButton));
      await tester.pump();
      expect(find.text('1'), findsOneWidget);
      expect(_swatchColor(tester), AppPalette.burgundyChampagne.ink);

      AppColors.current = AppPalette.warmSand;
      rebuildWholeTree(tester.element(find.byType(MaterialApp)));
      await tester.pump();

      expect(_swatchColor(tester), AppPalette.warmSand.ink);
      expect(
        tester.widget<Text>(find.text('1')).style?.color,
        AppPalette.warmSand.text,
      );
    },
  );
}
