import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:social_world/features/chat/presentation/widgets/swipe_back.dart';

void main() {
  const quick = Duration(milliseconds: 300);

  group('isBackSwipe', () {
    test('длинный пологий протяг вправо — выход', () {
      expect(isBackSwipe(dx: 180, dy: 20, elapsed: quick), isTrue);
    });

    test('короткий, вертикальный, влево и медленный — нет', () {
      expect(isBackSwipe(dx: 90, dy: 5, elapsed: quick), isFalse);
      expect(isBackSwipe(dx: 160, dy: 140, elapsed: quick), isFalse);
      expect(isBackSwipe(dx: -200, dy: 0, elapsed: quick), isFalse);
      expect(isBackSwipe(dx: 200, dy: 10, elapsed: const Duration(seconds: 2)), isFalse);
    });
  });

  group('SwipeBackToExit', () {
    setUp(() => SharedPreferences.setMockInitialValues({'swipe_back_hint_count': 3}));

    Future<int> pump(WidgetTester tester, Offset drag) async {
      var exits = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SwipeBackToExit(
              onExit: () => exits++,
              child: const SizedBox.expand(child: ColoredBox(color: Colors.black)),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await tester.dragFrom(const Offset(40, 300), drag);
      await tester.pump();
      return exits;
    }

    testWidgets('свайп вправо закрывает экран', (tester) async {
      expect(await pump(tester, const Offset(220, 10)), 1);
    });

    testWidgets('свайп влево (ответ на сообщение) экран не закрывает', (tester) async {
      expect(await pump(tester, const Offset(-220, 0)), 0);
    });

    testWidgets('вертикальная прокрутка экран не закрывает', (tester) async {
      expect(await pump(tester, const Offset(20, 300)), 0);
    });
  });
}
