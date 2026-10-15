import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/core/widgets/link_text.dart';

void main() {
  Widget host(String text) => MaterialApp(
    home: Scaffold(body: LinkText(text, readableLinks: true, hashtags: true)),
  );

  testWidgets('подпись в скобках показывается вместо адреса', (tester) async {
    await tester.pumpWidget(host('Источник: [Википедия](https://ru.wikipedia.org/wiki/%D0%A1) и всё'));
    expect(find.textContaining('Википедия', findRichText: true), findsOneWidget);
    expect(find.textContaining('%D0', findRichText: true), findsNothing);
    expect(find.textContaining('Источник: ', findRichText: true), findsOneWidget);
  });

  testWidgets('голый длинный адрес сокращается до имени сайта', (tester) async {
    await tester.pumpWidget(host('Смотрите https://www.example.com/very/long/path?x=1 сегодня.'));
    final text = tester.widget<RichText>(find.byType(RichText).last).text.toPlainText();
    expect(text, 'Смотрите example.com сегодня.');
  });
}
