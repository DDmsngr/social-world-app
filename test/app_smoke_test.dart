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
    await tester.pumpAndSettle();

    expect(find.text('Получить код'), findsOneWidget);
  });
}
