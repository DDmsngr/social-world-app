import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/features/chat/data/crypto/chat_crypto_service.dart';
import 'package:social_world/features/chat/data/crypto/chat_key_storage.dart';
import 'package:social_world/features/chat/data/crypto/peer_key_pins.dart';

// Восстановление переписки после переустановки (0084), на уровне шифрования:
// те же вызовы, что делает SecureChatRepository._rekeyForPeer и _openRekey.

void main() {
  test('Лёша переустановил приложение: Вика перекладывает их переписку, и Лёша её читает', () async {
    const conv = 'conv-1';
    final vika = await ChatCryptoService.initialize(userId: 'vika', storage: MemoryChatKeyStorage());
    final oldLesha = await ChatCryptoService.initialize(userId: 'lesha', storage: MemoryChatKeyStorage());
    final vikaKeys = await vika.publicKeys;
    final oldLeshaKeys = await oldLesha.publicKeys;

    // До переустановки: одно сообщение от Лёши, одно от Вики.
    final fromLesha = await oldLesha.encrypt(
      conversationId: conv, messageId: 'm1', senderId: 'lesha',
      recipientExchangeKey: vikaKeys.exchangeKey, text: 'привет от Лёши',
    );
    final fromVika = await vika.encrypt(
      conversationId: conv, messageId: 'm2', senderId: 'vika',
      recipientExchangeKey: oldLeshaKeys.exchangeKey, text: 'привет от Вики',
    );

    // Переустановка: у Лёши новые ключи, прежние стёрты.
    final newLesha = await ChatCryptoService.initialize(userId: 'lesha', storage: MemoryChatKeyStorage());
    final newLeshaKeys = await newLesha.publicKeys;
    await expectLater(
      newLesha.decrypt(
        conversationId: conv, messageId: 'm2', senderId: 'vika',
        peerExchangeKey: vikaKeys.exchangeKey, senderSigningKey: vikaKeys.signingKey, payload: fromVika,
      ),
      throwsA(anything),
      reason: 'без перекладки прежнее сообщение не открыть',
    );

    // Телефон Вики помнит прежний ключ Лёши (закреплённый) и перекладывает.
    final old = peerKeyFingerprint(oldLeshaKeys).split('|');
    Future<EncryptedChatPayload> rekey(String id, String sender, EncryptedChatPayload p) async {
      final clear = (await vika.decrypt(
        conversationId: conv, messageId: id, senderId: sender,
        peerExchangeKey: old[0],
        senderSigningKey: sender == 'vika' ? vikaKeys.signingKey : old[1],
        payload: p,
      )).text!;
      return vika.encrypt(
        conversationId: conv, messageId: id, senderId: 'vika',
        recipientExchangeKey: newLeshaKeys.exchangeKey, text: clear,
      );
    }

    final copy1 = await rekey('m1', 'lesha', fromLesha);
    final copy2 = await rekey('m2', 'vika', fromVika);

    Future<String?> open(String id, EncryptedChatPayload copy) async => (await newLesha.decrypt(
      conversationId: conv, messageId: id, senderId: 'vika',
      peerExchangeKey: vikaKeys.exchangeKey, senderSigningKey: vikaKeys.signingKey, payload: copy,
    )).text;

    expect(await open('m1', copy1), 'привет от Лёши');
    expect(await open('m2', copy2), 'привет от Вики');
  });

  test('копию, подписанную не собеседником, не принимаем', () async {
    const conv = 'conv-1';
    final vika = await ChatCryptoService.initialize(userId: 'vika', storage: MemoryChatKeyStorage());
    final stranger = await ChatCryptoService.initialize(userId: 'x', storage: MemoryChatKeyStorage());
    final lesha = await ChatCryptoService.initialize(userId: 'lesha', storage: MemoryChatKeyStorage());
    final vikaKeys = await vika.publicKeys;
    final forged = await stranger.encrypt(
      conversationId: conv, messageId: 'm1', senderId: 'vika',
      recipientExchangeKey: (await lesha.publicKeys).exchangeKey, text: 'подделка',
    );
    final opened = await lesha.decrypt(
      conversationId: conv, messageId: 'm1', senderId: 'vika',
      peerExchangeKey: vikaKeys.exchangeKey, senderSigningKey: vikaKeys.signingKey, payload: forged,
    );
    expect(opened.text, isNull);
  });

  test('прежние ключи и отметка «переложено» запоминаются', () async {
    final pins = MemoryPeerKeyPins();
    await pins.rememberPrevious('lesha', 'a|b');
    await pins.rememberPrevious('lesha', 'a|b');
    expect(await pins.previous('lesha'), ['a|b']);
    expect(await pins.rekeyed('lesha', 'c|d'), isFalse);
    await pins.markRekeyed('lesha', 'c|d');
    expect(await pins.rekeyed('lesha', 'c|d'), isTrue);
  });
}
