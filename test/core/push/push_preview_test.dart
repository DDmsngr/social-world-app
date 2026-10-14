import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/core/push/push_preview.dart';
import 'package:social_world/features/chat/data/crypto/chat_crypto_service.dart';
import 'package:social_world/features/chat/data/crypto/chat_key_storage.dart';

void main() {
  test('ключей нет — hasKeys «нет», и сам он их не создаёт', () async {
    final storage = MemoryChatKeyStorage();
    expect(await ChatCryptoService.hasKeys(userId: 'me', storage: storage), isFalse);
    expect(await ChatCryptoService.hasKeys(userId: 'me', storage: storage), isFalse);
    await ChatCryptoService.initialize(userId: 'me', storage: storage);
    expect(await ChatCryptoService.hasKeys(userId: 'me', storage: storage), isTrue);
    expect(await ChatCryptoService.hasKeys(userId: 'other', storage: storage), isFalse);
  });

  test('пуш не о личном сообщении — текст не ищем, остаётся то, что прислал сервер', () async {
    expect(await directMessagePreview({'type': 'notification'}), isNull);
    // Группа: текст уже в пуше, сервер e2e не ставит.
    expect(await directMessagePreview({'type': 'message', 'conversation_id': 'c', 'message_id': 'm'}), isNull);
    expect(await directMessagePreview({'type': 'message', 'e2e': '1', 'conversation_id': 'c'}), isNull);
  });

  test('шифровка туда и обратно: то, что расшифрует шторка, совпадает с отправленным', () async {
    final alice = await ChatCryptoService.initialize(userId: 'alice', storage: MemoryChatKeyStorage());
    final bob = await ChatCryptoService.initialize(userId: 'bob', storage: MemoryChatKeyStorage());
    final aliceKeys = await alice.publicKeys;
    final bobKeys = await bob.publicKeys;
    final payload = await alice.encrypt(
      conversationId: 'c',
      messageId: 'm',
      senderId: 'alice',
      recipientExchangeKey: bobKeys.exchangeKey,
      text: 'привет, как дела',
    );
    final opened = await bob.decrypt(
      conversationId: 'c',
      messageId: 'm',
      senderId: 'alice',
      peerExchangeKey: aliceKeys.exchangeKey,
      senderSigningKey: aliceKeys.signingKey,
      payload: payload,
    );
    expect(opened.text, 'привет, как дела');
  });
}
