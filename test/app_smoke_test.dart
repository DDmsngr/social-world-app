import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:social_world/app.dart';

void main() {
  setUpAll(() {
    // В тестах шрифты не тянем по сети — берём то, что есть в рантайме.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('без сессии приложение открывает вход', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: SocialWorldApp()));
    // Заставка держится минимум 700 мс осознанно (см. app_router.dart) —
    // без этого hero-баннер не успевал бы нарисовать ни кадра при мгновенно
    // восстановленной сессии. pumpAndSettle сам это время не мотает: без
    // активной анимации он останавливается на первом же устоявшемся кадре.
    await tester.pump(const Duration(milliseconds: 750));
    await tester.pumpAndSettle();

    expect(find.text('Получить код'), findsOneWidget);
  });
}
