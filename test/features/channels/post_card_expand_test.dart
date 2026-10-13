import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/features/channels/data/channels_repository.dart';
import 'package:social_world/features/channels/presentation/widgets/channel_post_card.dart';
import 'package:social_world/features/chat/domain/entities/chat_message.dart';

ChannelPost _post(String text) => ChannelPost(
  message: ChatMessage(
    id: 'p1',
    conversationId: 'ch',
    senderId: 'owner',
    sentAt: DateTime(2026, 10, 1, 9),
    text: text,
  ),
  commentCount: 0,
);

Future<List<String>> _pump(WidgetTester tester, String text) async {
  final events = <String>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ChannelPostCard(
            post: _post(text),
            onComments: () => events.add('comments'),
            onTap: (_) => events.add('react'),
          ),
        ),
      ),
    ),
  );
  return events;
}

final _long = List.generate(40, (i) => 'Абзац номер $i. ' * 3).join('\n\n');

void main() {
  testWidgets('длинный пост обрезан, тап разворачивает на месте', (tester) async {
    final events = await _pump(tester, _long);
    expect(find.text('Читать дальше'), findsOneWidget);
    expect(find.textContaining('Абзац номер 39'), findsNothing);

    await tester.tap(find.textContaining('Абзац номер 0'));
    await tester.pump();
    expect(events, isEmpty);
    expect(find.text('Свернуть'), findsOneWidget);
    expect(find.textContaining('Абзац номер 39'), findsOneWidget);
  });

  testWidgets('развёрнутый пост по тапу открывает реакции, «Свернуть» сворачивает', (tester) async {
    final events = await _pump(tester, _long);
    await tester.tap(find.text('Читать дальше'));
    await tester.pump();

    await tester.tap(find.textContaining('Абзац номер 0'));
    await tester.pump();
    expect(events, ['react']);

    await tester.ensureVisible(find.text('Свернуть'));
    await tester.pump();
    await tester.tap(find.text('Свернуть'));
    await tester.pump();
    expect(find.text('Читать дальше'), findsOneWidget);
    expect(find.textContaining('Абзац номер 39'), findsNothing);
  });

  testWidgets('короткий пост без обрезки: тап сразу открывает реакции', (tester) async {
    final events = await _pump(tester, 'Короткий пост про город');
    expect(find.text('Читать дальше'), findsNothing);
    await tester.tap(find.text('Короткий пост про город'));
    await tester.pump();
    expect(events, ['react']);
  });
}
