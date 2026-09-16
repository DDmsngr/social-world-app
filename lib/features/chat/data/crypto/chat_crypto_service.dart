import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'chat_key_storage.dart';

class ChatPublicKeys {
  const ChatPublicKeys({required this.exchangeKey, required this.signingKey});

  final String exchangeKey;
  final String signingKey;
}

class EncryptedChatPayload {
  const EncryptedChatPayload({
    required this.ciphertext,
    required this.nonce,
    required this.mac,
    required this.signature,
  });

  final String ciphertext;
  final String nonce;
  final String mac;
  final String signature;

  EncryptedChatPayload copyWith({String? signature}) => EncryptedChatPayload(
    ciphertext: ciphertext,
    nonce: nonce,
    mac: mac,
    signature: signature ?? this.signature,
  );
}

class DecryptedChatPayload {
  const DecryptedChatPayload({this.text, required this.signatureValid});

  final String? text;
  final bool signatureValid;
}

class ChatCryptoService {
  ChatCryptoService._(
    this._exchangeKeyPair,
    this._signingKeyPair, {
    required this.userId,
  });

  static const protocolVersion = 1;
  static const _keyPrefix = 'social-world-chat-v1';

  final String userId;
  final SimpleKeyPair _exchangeKeyPair;
  final SimpleKeyPair _signingKeyPair;
  final _exchange = X25519();
  final _signer = Ed25519();
  final _cipher = Chacha20.poly1305Aead();
  final _kdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  static Future<ChatCryptoService> initialize({
    required String userId,
    required ChatKeyStorage storage,
  }) async {
    final exchange = X25519();
    final signer = Ed25519();
    final exchangeStorageKey = '$_keyPrefix.$userId.x25519';
    final signingStorageKey = '$_keyPrefix.$userId.ed25519';

    final storedExchange = await storage.read(exchangeStorageKey);
    final storedSigning = await storage.read(signingStorageKey);

    final exchangeKeyPair = storedExchange == null
        ? await exchange.newKeyPair()
        : await exchange.newKeyPairFromSeed(base64Decode(storedExchange));
    final signingKeyPair = storedSigning == null
        ? await signer.newKeyPair()
        : await signer.newKeyPairFromSeed(base64Decode(storedSigning));

    if (storedExchange == null) {
      await storage.write(
        exchangeStorageKey,
        base64Encode(await exchangeKeyPair.extractPrivateKeyBytes()),
      );
    }
    if (storedSigning == null) {
      await storage.write(
        signingStorageKey,
        base64Encode(await signingKeyPair.extractPrivateKeyBytes()),
      );
    }

    return ChatCryptoService._(exchangeKeyPair, signingKeyPair, userId: userId);
  }

  Future<ChatPublicKeys> get publicKeys async {
    final exchangeKey = await _exchangeKeyPair.extractPublicKey();
    final signingKey = await _signingKeyPair.extractPublicKey();
    return ChatPublicKeys(
      exchangeKey: base64Encode(exchangeKey.bytes),
      signingKey: base64Encode(signingKey.bytes),
    );
  }

  Future<EncryptedChatPayload> encrypt({
    required String conversationId,
    required String messageId,
    required String senderId,
    required String recipientExchangeKey,
    required String text,
  }) async {
    final secretKey = await _conversationKey(
      conversationId,
      recipientExchangeKey,
    );
    final aad = _aad(conversationId, messageId, senderId);
    final box = await _cipher.encrypt(
      utf8.encode(text),
      secretKey: secretKey,
      aad: aad,
    );
    final signedBytes = _signedBytes(
      conversationId: conversationId,
      messageId: messageId,
      senderId: senderId,
      nonce: box.nonce,
      ciphertext: box.cipherText,
      mac: box.mac.bytes,
    );
    final signature = await _signer.sign(signedBytes, keyPair: _signingKeyPair);

    return EncryptedChatPayload(
      ciphertext: base64Encode(box.cipherText),
      nonce: base64Encode(box.nonce),
      mac: base64Encode(box.mac.bytes),
      signature: base64Encode(signature.bytes),
    );
  }

  Future<DecryptedChatPayload> decrypt({
    required String conversationId,
    required String messageId,
    required String senderId,
    required String peerExchangeKey,
    required String senderSigningKey,
    required EncryptedChatPayload payload,
  }) async {
    final nonce = base64Decode(payload.nonce);
    final ciphertext = base64Decode(payload.ciphertext);
    final mac = base64Decode(payload.mac);
    final signingKey = SimplePublicKey(
      base64Decode(senderSigningKey),
      type: KeyPairType.ed25519,
    );
    final signatureValid = await _signer.verify(
      _signedBytes(
        conversationId: conversationId,
        messageId: messageId,
        senderId: senderId,
        nonce: nonce,
        ciphertext: ciphertext,
        mac: mac,
      ),
      signature: Signature(
        base64Decode(payload.signature),
        publicKey: signingKey,
      ),
    );
    if (!signatureValid) {
      return const DecryptedChatPayload(signatureValid: false);
    }

    final clearText = await _cipher.decrypt(
      SecretBox(ciphertext, nonce: nonce, mac: Mac(mac)),
      secretKey: await _conversationKey(conversationId, peerExchangeKey),
      aad: _aad(conversationId, messageId, senderId),
    );
    return DecryptedChatPayload(
      text: utf8.decode(clearText),
      signatureValid: true,
    );
  }

  Future<String> securityCode({
    required String conversationId,
    required String peerExchangeKey,
  }) async {
    final key = await _conversationKey(conversationId, peerExchangeKey);
    final digest = await Sha256().hash(await key.extractBytes());
    final hex = digest.bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase()
        .substring(0, 40);
    return [
      for (var i = 0; i < hex.length; i += 5) hex.substring(i, i + 5),
    ].join(' ');
  }

  Future<SecretKey> _conversationKey(
    String conversationId,
    String peerExchangeKey,
  ) async {
    final peerKey = SimplePublicKey(
      base64Decode(peerExchangeKey),
      type: KeyPairType.x25519,
    );
    final sharedSecret = await _exchange.sharedSecretKey(
      keyPair: _exchangeKeyPair,
      remotePublicKey: peerKey,
    );
    return _kdf.deriveKey(
      secretKey: sharedSecret,
      nonce: utf8.encode(conversationId),
      info: utf8.encode(_keyPrefix),
    );
  }

  List<int> _aad(String conversationId, String messageId, String senderId) =>
      utf8.encode('$_keyPrefix|$conversationId|$messageId|$senderId');

  Uint8List _signedBytes({
    required String conversationId,
    required String messageId,
    required String senderId,
    required List<int> nonce,
    required List<int> ciphertext,
    required List<int> mac,
  }) => Uint8List.fromList([
    ..._aad(conversationId, messageId, senderId),
    ...nonce,
    ...ciphertext,
    ...mac,
  ]);
}
