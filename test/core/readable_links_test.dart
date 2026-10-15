import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/core/widgets/link_text.dart';

void main() {
  urlTests();
  Widget host(String text) => MaterialApp(
    home: Scaffold(body: LinkText(text, readableLinks: true, hashtags: true)),
  );

  testWidgets('подпись в скобках показывается вместо адреса', (tester) async {
    await tester.pumpWidget(host('Источник: [Википедия](https://ru.wikipedia.org/wiki/%D0%A1) и всё'));
    expect(find.textContaining('Википедия', findRichText: true), findsOneWidget);
    expect(find.textContaining('%D0', findRichText: true), findsNothing);
    expect(find.textContaining('Источник: ', findRichText: true), findsOneWidget);
  });

  testWidgets('скобки в адресе не обрывают ссылку', (tester) async {
    await tester.pumpWidget(host('Источник: [Википедия](https://ru.wikipedia.org/wiki/Парк_(Сочи)) и всё'));
    final text = tester.widget<RichText>(find.byType(RichText).last).text.toPlainText();
    expect(text, 'Источник: Википедия и всё');
  });

  testWidgets('голый длинный адрес сокращается до имени сайта', (tester) async {
    await tester.pumpWidget(host('Смотрите https://www.example.com/very/long/path?x=1 сегодня.'));
    final text = tester.widget<RichText>(find.byType(RichText).last).text.toPlainText();
    expect(text, 'Смотрите example.com сегодня.');
  });
}

void urlTests() {
  test('адрес в диалоге показывается буквами, битый остаётся как есть', () {
    expect(readableUrl('https://ru.wikipedia.org/wiki/%D0%A1%D0%BE%D1%87%D0%B8'), 'https://ru.wikipedia.org/wiki/Сочи');
    expect(readableUrl('https://x.org/%E0%A4%A'), 'https://x.org/%E0%A4%A');
  });
}
