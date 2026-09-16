import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/features/chat/data/crypto/chat_crypto_service.dart';
import 'package:social_world/features/chat/data/crypto/chat_key_storage.dart';

void main() {
  late ChatCryptoService alice;
  late ChatCryptoService bob;
  late ChatCryptoService charlie;
  late ChatPublicKeys aliceKeys;
  late ChatPublicKeys bobKeys;

  setUp(() async {
    final storage = MemoryChatKeyStorage();
    alice = await ChatCryptoService.initialize(
      userId: 'alice',
      storage: storage,
    );
    bob = await ChatCryptoService.initialize(userId: 'bob', storage: storage);
    charlie = await ChatCryptoService.initialize(
      userId: 'charlie',
      storage: storage,
    );
    aliceKeys = await alice.publicKeys;
    bobKeys = await bob.publicKeys;
  });

  test('шифрование и расшифровка возвращают исходный текст', () async {
    const text = 'Встречаемся у моря в семь';
    final encrypted = await alice.encrypt(
      conversationId: 'conversation-1',
      messageId: 'message-1',
      senderId: 'alice',
      recipientExchangeKey: bobKeys.exchangeKey,
      text: text,
    );
    final decrypted = await bob.decrypt(
      conversationId: 'conversation-1',
      messageId: 'message-1',
      senderId: 'alice',
      peerExchangeKey: aliceKeys.exchangeKey,
      senderSigningKey: aliceKeys.signingKey,
      payload: encrypted,
    );

    expect(decrypted.text, text);
    expect(decrypted.signatureValid, isTrue);
  });

  test('чужой приватный ключ не расшифровывает сообщение', () async {
    final encrypted = await alice.encrypt(
      conversationId: 'conversation-1',
      messageId: 'message-2',
      senderId: 'alice',
      recipientExchangeKey: bobKeys.exchangeKey,
      text: 'Секрет',
    );

    expect(
      () => charlie.decrypt(
        conversationId: 'conversation-1',
        messageId: 'message-2',
        senderId: 'alice',
        peerExchangeKey: aliceKeys.exchangeKey,
        senderSigningKey: aliceKeys.signingKey,
        payload: encrypted,
      ),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });

  test('подделанная подпись обнаруживается до расшифровки', () async {
    final encrypted = await alice.encrypt(
      conversationId: 'conversation-1',
      messageId: 'message-3',
      senderId: 'alice',
      recipientExchangeKey: bobKeys.exchangeKey,
      text: 'Подписанный текст',
    );
    final signature = base64Decode(encrypted.signature)..first ^= 0x01;
    final decrypted = await bob.decrypt(
      conversationId: 'conversation-1',
      messageId: 'message-3',
      senderId: 'alice',
      peerExchangeKey: aliceKeys.exchangeKey,
      senderSigningKey: aliceKeys.signingKey,
      payload: encrypted.copyWith(signature: base64Encode(signature)),
    );

    expect(decrypted.text, isNull);
    expect(decrypted.signatureValid, isFalse);
  });

  test('код безопасности совпадает у обоих собеседников', () async {
    final aliceCode = await alice.securityCode(
      conversationId: 'conversation-1',
      peerExchangeKey: bobKeys.exchangeKey,
    );
    final bobCode = await bob.securityCode(
      conversationId: 'conversation-1',
      peerExchangeKey: aliceKeys.exchangeKey,
    );

    expect(aliceCode, bobCode);
    expect(aliceCode.split(' '), hasLength(8));
  });
}
