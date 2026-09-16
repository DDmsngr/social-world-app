import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../domain/entities/chat_message.dart';
import '../domain/entities/conversation.dart';
import '../domain/repositories/chat_repository.dart';
import 'crypto/chat_crypto_service.dart';
import 'crypto/chat_key_storage.dart';

class SecureChatRepository implements ChatRepository {
  SecureChatRepository(
    this._client, {
    required this.currentUserId,
    ChatKeyStorage? keyStorage,
  }) : _keyStorage = keyStorage ?? SecureChatKeyStorage() {
    _ready = _initialize();
  }

  final SupabaseClient _client;
  final String currentUserId;
  final ChatKeyStorage _keyStorage;
  final _uuid = const Uuid();
  late final Future<ChatCryptoService> _ready;

  @override
  bool get endToEndEncryptionEnabled => true;

  Future<ChatCryptoService> _initialize() async {
    final crypto = await ChatCryptoService.initialize(
      userId: currentUserId,
      storage: _keyStorage,
    );
    final keys = await crypto.publicKeys;
    await _client.from('chat_public_keys').upsert({
      'profile_id': currentUserId,
      'x25519_public_key': keys.exchangeKey,
      'ed25519_public_key': keys.signingKey,
      'protocol_version': ChatCryptoService.protocolVersion,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    return crypto;
  }

  @override
  Future<List<Conversation>> loadConversations() async {
    await _ready;
    final memberships = await _client
        .from('chat_members')
        .select('conversation_id, last_read_at')
        .eq('profile_id', currentUserId)
        .order('joined_at', ascending: false);

    return Future.wait([
      for (final membership in memberships)
        _loadConversation(Map<String, dynamic>.from(membership)),
    ]);
  }

  Future<Conversation> _loadConversation(
    Map<String, dynamic> membership,
  ) async {
    final conversationId = membership['conversation_id'] as String;
    final peer = await _loadPeer(conversationId);
    final keys = await _loadPublicKeys(peer.id);
    final rows = await _client
        .from('chat_messages')
        .select()
        .eq('conversation_id', conversationId)
        .order('sent_at');
    final messages = keys == null
        ? const <ChatMessage>[]
        : await _decodeMessages(
            rows: rows,
            conversationId: conversationId,
            peer: peer,
            peerKeys: keys,
          );
    final lastReadAt = _date(membership['last_read_at']);
    final unreadCount = messages.where((message) {
      return message.senderId != currentUserId &&
          (lastReadAt == null || message.sentAt.isAfter(lastReadAt));
    }).length;

    return Conversation(
      id: conversationId,
      peerId: peer.id,
      peerName: peer.name,
      peerAvatarUrl: peer.avatarUrl,
      lastMessage: messages.lastOrNull,
      unreadCount: unreadCount,
      encrypted: keys != null,
    );
  }

  @override
  Stream<List<ChatMessage>> watchMessages(String conversationId) async* {
    await _ready;
    final peer = await _loadPeer(conversationId);
    final keys = await _loadPublicKeys(peer.id);
    if (keys == null) {
      throw StateError('Собеседник ещё не опубликовал ключи шифрования');
    }

    yield* _client
        .from('chat_messages')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', conversationId)
        .order('sent_at')
        .asyncMap(
          (rows) => _decodeMessages(
            rows: rows,
            conversationId: conversationId,
            peer: peer,
            peerKeys: keys,
          ),
        );
  }

  @override
  Future<ChatMessage> send({
    required String conversationId,
    required String text,
  }) async {
    final crypto = await _ready;
    final peer = await _loadPeer(conversationId);
    final keys = await _loadPublicKeys(peer.id);
    if (keys == null) {
      throw StateError('Собеседник ещё не опубликовал ключи шифрования');
    }

    final sentAt = DateTime.now().toUtc();
    final id = _uuid.v4();
    final payload = await crypto.encrypt(
      conversationId: conversationId,
      messageId: id,
      senderId: currentUserId,
      recipientExchangeKey: keys.exchangeKey,
      text: text.trim(),
    );
    await _client.from('chat_messages').insert({
      'id': id,
      'conversation_id': conversationId,
      'sender_id': currentUserId,
      'kind': 'text',
      'ciphertext': payload.ciphertext,
      'nonce': payload.nonce,
      'mac': payload.mac,
      'signature': payload.signature,
      'protocol_version': ChatCryptoService.protocolVersion,
      'sent_at': sentAt.toIso8601String(),
    });

    return ChatMessage(
      id: id,
      conversationId: conversationId,
      senderId: currentUserId,
      sentAt: sentAt,
      text: text.trim(),
      status: MessageStatus.sent,
      signatureValid: true,
    );
  }

  @override
  Future<void> markRead(String conversationId) async {
    await _ready;
    await _client
        .from('chat_members')
        .update({'last_read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('conversation_id', conversationId)
        .eq('profile_id', currentUserId);
  }

  @override
  Future<String> securityCode(String conversationId) async {
    final crypto = await _ready;
    final peer = await _loadPeer(conversationId);
    final keys = await _loadPublicKeys(peer.id);
    if (keys == null) return 'Ключи собеседника ещё не получены';
    return crypto.securityCode(
      conversationId: conversationId,
      peerExchangeKey: keys.exchangeKey,
    );
  }

  Future<List<ChatMessage>> _decodeMessages({
    required List<Map<String, dynamic>> rows,
    required String conversationId,
    required _Peer peer,
    required ChatPublicKeys peerKeys,
  }) async {
    final crypto = await _ready;
    final myKeys = await crypto.publicKeys;
    return Future.wait([
      for (final row in rows)
        _decodeMessage(
          crypto: crypto,
          row: row,
          conversationId: conversationId,
          peer: peer,
          peerKeys: peerKeys,
          myKeys: myKeys,
        ),
    ]);
  }

  Future<ChatMessage> _decodeMessage({
    required ChatCryptoService crypto,
    required Map<String, dynamic> row,
    required String conversationId,
    required _Peer peer,
    required ChatPublicKeys peerKeys,
    required ChatPublicKeys myKeys,
  }) async {
    final senderId = row['sender_id'] as String;
    final senderKeys = senderId == currentUserId ? myKeys : peerKeys;
    final sentAt = DateTime.parse(row['sent_at'] as String).toLocal();

    try {
      final decrypted = await crypto.decrypt(
        conversationId: conversationId,
        messageId: row['id'] as String,
        senderId: senderId,
        peerExchangeKey: peerKeys.exchangeKey,
        senderSigningKey: senderKeys.signingKey,
        payload: EncryptedChatPayload(
          ciphertext: row['ciphertext'] as String,
          nonce: row['nonce'] as String,
          mac: row['mac'] as String,
          signature: row['signature'] as String,
        ),
      );
      return ChatMessage(
        id: row['id'] as String,
        conversationId: conversationId,
        senderId: senderId,
        sentAt: sentAt,
        text: decrypted.text ?? 'Сообщение не прошло проверку подписи',
        status: _status(sentAt, peer.lastReadAt),
        signatureValid: decrypted.signatureValid,
      );
    } catch (_) {
      return ChatMessage(
        id: row['id'] as String,
        conversationId: conversationId,
        senderId: senderId,
        sentAt: sentAt,
        text: 'Не удалось расшифровать сообщение',
        status: MessageStatus.failed,
        signatureValid: false,
      );
    }
  }

  Future<_Peer> _loadPeer(String conversationId) async {
    final row = await _client
        .from('chat_members')
        .select(
          'profile_id, last_read_at, '
          'profiles!chat_members_profile_id_fkey(display_name, avatar_url)',
        )
        .eq('conversation_id', conversationId)
        .neq('profile_id', currentUserId)
        .limit(1)
        .maybeSingle();
    if (row == null) throw StateError('Собеседник не найден');
    final profile = Map<String, dynamic>.from(row['profiles'] as Map);
    return _Peer(
      id: row['profile_id'] as String,
      name: profile['display_name'] as String? ?? 'Пользователь',
      avatarUrl: profile['avatar_url'] as String?,
      lastReadAt: _date(row['last_read_at']),
    );
  }

  Future<ChatPublicKeys?> _loadPublicKeys(String profileId) async {
    final row = await _client
        .from('chat_public_keys')
        .select('x25519_public_key, ed25519_public_key, protocol_version')
        .eq('profile_id', profileId)
        .maybeSingle();
    if (row == null ||
        row['protocol_version'] != ChatCryptoService.protocolVersion) {
      return null;
    }
    return ChatPublicKeys(
      exchangeKey: row['x25519_public_key'] as String,
      signingKey: row['ed25519_public_key'] as String,
    );
  }

  DateTime? _date(Object? value) =>
      value == null ? null : DateTime.parse(value as String).toLocal();

  MessageStatus _status(DateTime sentAt, DateTime? peerLastReadAt) =>
      peerLastReadAt != null && !peerLastReadAt.isBefore(sentAt)
      ? MessageStatus.read
      : MessageStatus.sent;
}

class _Peer {
  const _Peer({
    required this.id,
    required this.name,
    required this.avatarUrl,
    required this.lastReadAt,
  });

  final String id;
  final String name;
  final String? avatarUrl;
  final DateTime? lastReadAt;
}
