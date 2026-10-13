import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/features/channels/data/channels_repository.dart';
import 'package:social_world/features/channels/presentation/widgets/channel_topics_picker.dart';

void main() {
  group('темы канала', () {
    test('готовые подписываются по-русски, свои как есть', () {
      expect(channelTopicLabel('food'), 'Еда');
      expect(channelTopicLabel('настолки'), 'настолки');
    });

    test('у старой строки без списка тема одна — главная', () {
      expect(channelTopicsFrom(null, ChannelTopic.sport), ['sport']);
      expect(channelTopicsFrom(const ['food', 'кофе'], ChannelTopic.other), ['food', 'кофе']);
    });

    test('главная готовая тема — первая известная, иначе other', () {
      expect(primaryChannelTopic(['настолки', 'sport', 'food']), ChannelTopic.sport);
      expect(primaryChannelTopic(['настолки']), ChannelTopic.other);
      expect(primaryChannelTopic(const []), ChannelTopic.other);
    });
  });

  group('выбор тем', () {
    Future<List<String>> pump(WidgetTester tester, List<String> start) async {
      var topics = start;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => SingleChildScrollView(
                child: ChannelTopicsPicker(
                  topics: topics,
                  onChanged: (next) => setState(() => topics = next),
                ),
              ),
            ),
          ),
        ),
      );
      return topics;
    }

    testWidgets('готовые темы выбираются несколькими', (tester) async {
      await pump(tester, ['other']);
      await tester.tap(find.text('Еда'));
      await tester.pump();
      await tester.tap(find.text('Спорт'));
      await tester.pump();
      expect(find.text('Темы (до 5): 3'), findsOneWidget);
      await tester.tap(find.text('Еда'));
      await tester.pump();
      expect(find.text('Темы (до 5): 2'), findsOneWidget);
    });

    testWidgets('своя тема добавляется, дубль и короткая отвергаются', (tester) async {
      await pump(tester, ['food']);
      await tester.enterText(find.byType(TextField), 'Настолки');
      await tester.tap(find.byTooltip('Добавить тему'));
      await tester.pump();
      expect(find.widgetWithText(InputChip, 'Настолки'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'настолки');
      await tester.tap(find.byTooltip('Добавить тему'));
      await tester.pump();
      expect(find.text('Такая тема уже есть'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'я');
      await tester.tap(find.byTooltip('Добавить тему'));
      await tester.pump();
      expect(find.text('Тема: от 2 до 24 знаков'), findsOneWidget);
    });

    testWidgets('больше пяти тем не набрать', (tester) async {
      await pump(tester, ['food', 'sport', 'news', 'memes', 'city']);
      await tester.enterText(find.byType(TextField), 'шестая');
      await tester.tap(find.byTooltip('Добавить тему'));
      await tester.pump();
      expect(find.text('Не больше 5 тем'), findsOneWidget);
    });

    testWidgets('свою тему можно убрать крестиком', (tester) async {
      await pump(tester, ['food', 'настолки']);
      expect(find.widgetWithText(InputChip, 'настолки'), findsOneWidget);
      await tester.tap(find.descendant(of: find.widgetWithText(InputChip, 'настолки'), matching: find.byType(Icon)));
      await tester.pump();
      expect(find.widgetWithText(InputChip, 'настолки'), findsNothing);
    });
  });
}
