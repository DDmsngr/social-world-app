import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/features/chat/data/local_chat_repository.dart';

// Заглушка повторяет правила delete_chat_messages (миграция 0033): своё
// удаляется у всех, чужое в личном — нет. Правило для групп — в
// message_actions_test.
void main() {
  late LocalChatRepository repository;

  setUp(() => repository = LocalChatRepository(currentUserId: () => 'me'));
  tearDown(() => repository.dispose());

  test('своё сообщение пропадает из потока', () async {
    final sent = await repository.send(conversationId: 'conv-1', text: 'Ой');
    final deleted = await repository.deleteForEveryone([sent]);
    expect(deleted, {sent.id});
    final thread = await repository.watchMessages('conv-1').first;
    expect(thread.map((m) => m.id), isNot(contains(sent.id)));
  });

  test('чужое в личном диалоге у всех не удаляется', () async {
    final thread = await repository.watchMessages('conv-1').first;
    final peer = thread.firstWhere((m) => m.senderId != 'me');
    expect(await repository.deleteForEveryone([peer]), isEmpty);
    final after = await repository.watchMessages('conv-1').first;
    expect(after.map((m) => m.id), contains(peer.id));
  });

  test('после удаления превью чата — предыдущее сообщение', () async {
    final sent = await repository.send(conversationId: 'conv-2', text: 'Упс');
    await repository.deleteForEveryone([sent]);
    final after = (await repository.loadConversations())
        .firstWhere((c) => c.id == 'conv-2')
        .lastMessage;
    expect(after?.id, 'conv-2-1');
  });
}
