import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:social_world/app.dart';
import 'package:social_world/core/theme/app_colors.dart';
import 'package:social_world/core/theme/theme_choice.dart';

void main() {
  setUpAll(() {
    // В тестах шрифты не тянем по сети — берём то, что есть в рантайме.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  tearDown(() => AppColors.current = AppPalette.burgundyChampagne);

  Future<void> passSplash(WidgetTester tester) async {
    // Заставка держится 1,7 с осознанно (см. app_router.dart) — без этого
    // hero-баннер не успевал бы нарисовать ни кадра при мгновенно
    // восстановленной сессии. pumpAndSettle сам это время не мотает: без
    // активной анимации он останавливается на первом же устоявшемся кадре.
    await tester.pump(const Duration(milliseconds: 1750));
    await tester.pumpAndSettle();
  }

  testWidgets('без сессии приложение открывает вход', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: SocialWorldApp()));
    await passSplash(tester);

    expect(find.text('Получить код'), findsOneWidget);
  });

  testWidgets('сохранённая светлая тема применяется с первого экрана', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialThemeChoiceProvider.overrideWithValue(ThemeChoice.light),
        ],
        child: const SocialWorldApp(),
      ),
    );
    await passSplash(tester);

    expect(find.text('Получить код'), findsOneWidget);
    expect(AppColors.current, same(AppPalette.warmSand));
    expect(
      Theme.of(tester.element(find.text('Получить код'))).scaffoldBackgroundColor,
      AppPalette.warmSand.ink,
    );
  });
}
