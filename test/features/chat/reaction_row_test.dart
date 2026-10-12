import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/features/chat/domain/entities/chat_message.dart';
import 'package:social_world/features/chat/presentation/providers/chat_extras_providers.dart';
import 'package:social_world/features/chat/presentation/widgets/message_bubble.dart';
import 'package:social_world/features/chat/presentation/widgets/reaction_chips.dart';

void main() {
  testWidgets('реакции стоят на одной строке со временем, слева от него', (tester) async {
    final message = ChatMessage(
      id: 'm',
      conversationId: 'c',
      senderId: 'peer',
      sentAt: DateTime(2026, 10, 12, 21, 24),
      text: 'Уже сделал',
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: message,
              mine: false,
              reactions: ReactionChips(
                reactions: const [ReactionCount(emoji: '👍', count: 1, mine: true)],
                mine: false,
                onTap: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    final chip = tester.getRect(find.text('👍 1'));
    final time = tester.getRect(find.text('21:24'));

    expect(time.left, greaterThan(chip.right), reason: 'время правее реакции');
    expect((time.center.dy - chip.center.dy).abs(), lessThan(chip.height), reason: 'одна строка');
  });
}
