import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/features/shell/presentation/home_shell.dart';

void main() {
  group('нижняя навигация в переписке', () {
    test('только в переписке и только пока открыта клавиатура или эмодзи', () {
      bool show({bool inChat = true, bool keyboard = false, bool emoji = false}) =>
          HomeShell.showBottomNav(
            inChat: inChat,
            keyboard: keyboard,
            emojiPanel: emoji,
          );
      expect(show(), isTrue, reason: 'в переписке без клавиатуры — иконки');
      expect(show(keyboard: true), isFalse);
      expect(show(emoji: true), isFalse);
      // Вне переписки навигацию не прячем никогда.
      expect(show(inChat: false, keyboard: true, emoji: true), isTrue);
    });

    test('переписка — это /chats/<id>, но не список и не создание группы', () {
      expect(HomeShell.isConversation('/chats/abc'), isTrue);
      expect(HomeShell.isConversation('/chats/abc/info'), isTrue);
      expect(HomeShell.isConversation('/chats'), isFalse);
      expect(HomeShell.isConversation('/chats/new-group'), isFalse);
      expect(HomeShell.isConversation('/feed'), isFalse);
    });
  });

  // Регрессия: когда навигацию прятали пустым виджетом, Scaffold всё равно
  // считал системную полосу снизу занятой и убирал отступ у тела — поле ввода
  // уезжало под системные кнопки Android. Прячем null-ом.
  group('системная полоса снизу', () {
    Future<double> bottomPadding(
      WidgetTester tester, {
      required Widget? bar,
    }) async {
      double? seen;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(padding: EdgeInsets.only(bottom: 48)),
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: const MediaQueryData(padding: EdgeInsets.only(bottom: 48)),
              child: child!,
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  seen = MediaQuery.paddingOf(context).bottom;
                  return const SizedBox();
                },
              ),
              bottomNavigationBar: bar,
            ),
          ),
        ),
      );
      return seen!;
    }

    testWidgets('без панели (null) отступ снизу остаётся — SafeArea сработает', (
      tester,
    ) async {
      expect(await bottomPadding(tester, bar: null), 48);
    });

    testWidgets('пустая панель отступ съедает — поэтому её нельзя использовать', (
      tester,
    ) async {
      expect(await bottomPadding(tester, bar: const SizedBox.shrink()), 0);
    });
  });
}
