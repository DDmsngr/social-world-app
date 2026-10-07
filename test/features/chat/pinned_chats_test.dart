import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/features/chat/domain/entities/chat_message.dart';
import 'package:social_world/features/chat/domain/entities/conversation.dart';
import 'package:social_world/features/chat/presentation/providers/pinned_chats.dart';

Conversation _c(String id, int? minute) => Conversation(
  id: id,
  lastMessage: minute == null
      ? null
      : ChatMessage(id: 'm$id', conversationId: id, senderId: 'x', sentAt: DateTime(2026, 10, 7, 20, minute)),
);

void main() {
  test('свежий пост выше, закреплённые сверху в порядке закрепления', () {
    final sorted = sortChats(
      [_c('old', 1), _c('empty', null), _c('new', 30), _c('pinA', 2), _c('pinB', 3)],
      ['pinB', 'pinA'],
    );
    expect([for (final c in sorted) c.id], ['pinB', 'pinA', 'new', 'old', 'empty']);
  });
}
