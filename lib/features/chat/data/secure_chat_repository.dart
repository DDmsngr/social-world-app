import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/debug/app_log.dart';
import '../domain/entities/chat_message.dart';
import '../domain/entities/conversation.dart';
import '../domain/repositories/chat_repository.dart';
import 'chat_media_cache.dart';
import 'crypto/chat_crypto_service.dart';
import 'crypto/chat_key_storage.dart';

/// Потолок файла в Supabase Cloud (бесплатный тариф) — 50 МБ.
const maxAttachmentBytes = 50 * 1024 * 1024;

class ChatAttachmentTooLarge implements Exception {
  const ChatAttachmentTooLarge();

  @override
  String toString() => 'Файл больше 50 МБ — такой не отправить';
}

const _bucket = 'chat-media';

/// Боевой чат на Supabase. Личные диалоги — сквозное шифрование, сервер
/// видит только шифротекст. Группы и квест-чаты — открытый текст в `body`
/// (решение 29.09): доступ к ним режут RLS и членство.
class SecureChatRepository implements ChatRepository {
  SecureChatRepository(
    this._client, {
    required this.currentUserId,
    ChatKeyStorage? keyStorage,
  }) : _keyStorage = keyStorage ?? SecureChatKeyStorage() {
    _ready = _initialize();
    // Ошибку публикации ключей получит тот, кто дождётся _ready; без
    // ожидающих она не должна всплывать как необработанная.
    _ready.ignore();
  }

  /// Сколько последних сообщений держит экран переписки.
  static const _historyLimit = 300;

  final SupabaseClient _client;
  final String currentUserId;
  final ChatKeyStorage _keyStorage;
  final _uuid = const Uuid();
  late final Future<ChatCryptoService> _ready;

  /// Тип чата не меняется — запоминаем, чтобы не спрашивать сервер на
  /// каждое сообщение.
  final _kinds = <String, ConversationKind>{};

  /// Опубликованные ключи не меняются без смены устройства; пустой ответ не
  /// кэшируется — собеседник может опубликовать ключи позже.
  final _keys = <String, ChatPublicKeys>{};

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
    final rows = await _client.rpc('my_chats') as List<dynamic>;
    return Future.wait([
      for (final row in rows) _conversationFromRow(row as Map<String, dynamic>),
    ]);
  }

  @override
  Future<Conversation> loadConversation(String conversationId) async {
    await _ready;
    final rows = await _client.rpc(
      'my_chats',
      params: {'in_conversation': conversationId},
    ) as List<dynamic>;
    if (rows.isEmpty) throw StateError('Чат недоступен');
    return _conversationFromRow(rows.first as Map<String, dynamic>);
  }

  Future<Conversation> _conversationFromRow(Map<String, dynamic> row) async {
    final id = row['id'] as String;
    final kind = ConversationKind.parse(row['kind']);
    _kinds[id] = kind;

    final peerId = row['peer_id'] as String?;
    final peerKeys = kind == ConversationKind.direct && peerId != null
        ? await _loadPublicKeys(peerId)
        : null;

    ChatMessage? last;
    final lastId = row['last_id'] as String?;
    if (lastId != null) {
      final senderId = row['last_sender_id'] as String;
      final sentAt = DateTime.parse(row['last_sent_at'] as String).toLocal();
      final lastKind = MessageKind.parse(row['last_kind']);
      if (kind == ConversationKind.direct) {
        last = peerKeys == null
            ? ChatMessage(
                id: lastId,
                conversationId: id,
                senderId: senderId,
                sentAt: sentAt,
                text: 'Зашифрованное сообщение',
              )
            : await _decodeDirect(
                row: {
                  'id': lastId,
                  'kind': row['last_kind'],
                  'sender_id': senderId,
                  'sent_at': row['last_sent_at'],
                  'ciphertext': row['last_ciphertext'],
                  'nonce': row['last_nonce'],
                  'mac': row['last_mac'],
                  'signature': row['last_signature'],
                },
                conversationId: id,
                peerKeys: peerKeys,
                peerLastReadAt: _date(row['peer_last_read_at']),
              );
      } else {
        last = ChatMessage(
          id: lastId,
          conversationId: id,
          senderId: senderId,
          sentAt: sentAt,
          kind: lastKind,
          text: row['last_body'] as String?,
          senderName: row['last_sender_name'] as String?,
        );
      }
    }

    return Conversation(
      id: id,
      kind: kind,
      peerId: peerId,
      peerName: row['peer_name'] as String?,
      peerAvatarUrl: row['peer_avatar'] as String?,
      title: row['title'] as String?,
      memberCount: (row['member_count'] as num?)?.toInt() ?? 0,
      isOwner: row['my_role'] == 'owner',
      closed: row['closed'] as bool? ?? false,
      lastMessage: last,
      unreadCount: (row['unread_count'] as num?)?.toInt() ?? 0,
      encrypted: kind == ConversationKind.direct && peerKeys != null,
    );
  }

  Future<ConversationKind> _kind(String conversationId) async =>
      _kinds[conversationId] ?? (await loadConversation(conversationId)).kind;

  @override
  Stream<List<ChatMessage>> watchMessages(String conversationId) async* {
    await _ready;
    final conversation = await loadConversation(conversationId);
    final rows = _client
        .from('chat_messages')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', conversationId)
        .order('sent_at', ascending: false)
        .limit(_historyLimit);

    if (conversation.isDirect) {
      final peerId = conversation.peerId;
      final keys = peerId == null ? null : await _loadPublicKeys(peerId);
      if (keys == null) {
        throw StateError('Собеседник ещё не опубликовал ключи шифрования');
      }
      final peerLastReadAt = await _peerLastReadAt(conversationId);
      yield* rows.asyncMap(
        (batch) => Future.wait([
          for (final row in batch.reversed)
            // Удалённое у всех — «надгробие» без содержимого (0033).
            if (row['deleted_at'] == null)
              _decodeDirect(
              row: row,
              conversationId: conversationId,
              peerKeys: keys,
              peerLastReadAt: peerLastReadAt,
            ),
        ]),
      );
      return;
    }

    final names = {
      for (final member in await loadMembers(conversationId))
        member.id: member.name,
    };
    yield* rows.asyncMap((batch) async {
      // Автор мог уже выйти из группы — имя добираем из профилей.
      final unknown = {
        for (final row in batch)
          if (!names.containsKey(row['sender_id'])) row['sender_id'] as String,
      };
      if (unknown.isNotEmpty) {
        final profiles = await _client
            .from('profiles')
            .select('id, display_name')
            .inFilter('id', unknown.toList());
        for (final p in profiles) {
          names[p['id'] as String] =
              p['display_name'] as String? ?? 'Участник';
        }
      }
      return [
        for (final row in batch.reversed)
          if (row['deleted_at'] == null)
            ChatMessage(
            id: row['id'] as String,
            conversationId: conversationId,
            senderId: row['sender_id'] as String,
            senderName: names[row['sender_id']] ?? 'Участник',
            sentAt: DateTime.parse(row['sent_at'] as String).toLocal(),
            kind: MessageKind.parse(row['kind']),
            text: row['body'] as String?,
            attachment: ChatAttachment.fromJson(row['media']),
          ),
      ];
    });
  }

  @override
  Future<Set<String>> deleteForEveryone(List<ChatMessage> messages) async {
    if (messages.isEmpty) return const {};
    final List<dynamic> rows;
    try {
      rows = await _client.rpc(
            'delete_chat_messages',
            params: {'in_ids': [for (final m in messages) m.id]},
          )
          as List<dynamic>;
    } on PostgrestException catch (error) {
      // Функции нет — миграция 0033 ещё не накатана на сервер.
      if (error.code == 'PGRST202' || error.code == '42883') {
        throw const ChatDeleteUnavailable();
      }
      rethrow;
    }
    final deleted = {for (final id in rows) id as String};

    // Файл убираем после строки: наоборот, при сбое осталось бы сообщение
    // со ссылкой в никуда. Чужой файл (владелец группы удаляет чужое)
    // хранилище не отдаст — он останется сиротой, это не страшно.
    final paths = [
      for (final m in messages)
        if (deleted.contains(m.id) && m.attachment != null) m.attachment!.path,
    ];
    if (paths.isNotEmpty) {
      await _client.storage.from(_bucket).remove(paths).catchError(
        (Object error) {
          AppLog.add('Файлы удалённых сообщений остались: $error');
          return <FileObject>[];
        },
      );
    }
    return deleted;
  }

  @override
  Future<ChatMessage> send({
    required String conversationId,
    required String text,
    MessageKind kind = MessageKind.text,
  }) async {
    final clean = text.trim();
    final id = _uuid.v4();
    await _insert(
      id: id,
      conversationId: conversationId,
      kind: kind,
      text: clean,
    );
    return ChatMessage(
      id: id,
      conversationId: conversationId,
      senderId: currentUserId,
      sentAt: DateTime.now(),
      kind: kind,
      text: clean,
      status: MessageStatus.sent,
      signatureValid: true,
    );
  }

  @override
  Future<ChatMessage> sendAttachment({
    required String conversationId,
    required MessageKind kind,
    required String filePath,
    String? name,
    String? mime,
    int? durationMs,
    List<double>? waveform,
    String? caption,
  }) async {
    await _ready;
    final clear = await File(filePath).readAsBytes();
    if (clear.length > maxAttachmentBytes) {
      throw const ChatAttachmentTooLarge();
    }
    final direct = await _kind(conversationId) == ConversationKind.direct;
    final id = _uuid.v4();
    final storagePath = '$conversationId/$id';

    String? key;
    Uint8List upload = clear;
    if (direct) {
      final encrypted = await ChatCryptoService.encryptFile(clear);
      upload = encrypted.bytes;
      key = encrypted.key;
    }
    await _client.storage
        .from(_bucket)
        .uploadBinary(
          storagePath,
          upload,
          fileOptions: FileOptions(
            contentType: direct
                ? 'application/octet-stream'
                : (mime ?? 'application/octet-stream'),
          ),
        );

    final attachment = ChatAttachment(
      path: storagePath,
      size: clear.length,
      name: name,
      mime: mime,
      durationMs: durationMs,
      waveform: waveform,
      key: key,
    );
    final text = caption?.trim();
    try {
      await _insert(
        id: id,
        conversationId: conversationId,
        kind: kind,
        text: text == null || text.isEmpty ? null : text,
        attachment: attachment,
      );
    } catch (_) {
      // Сообщение не записалось — файл без сообщения никому не нужен.
      await _client.storage.from(_bucket).remove([storagePath]).catchError(
        (_) => <FileObject>[],
      );
      rethrow;
    }
    await ChatMediaCache.keepSent(id, kind, filePath, name).catchError((_) {});

    return ChatMessage(
      id: id,
      conversationId: conversationId,
      senderId: currentUserId,
      sentAt: DateTime.now(),
      kind: kind,
      text: text,
      attachment: attachment,
      status: MessageStatus.sent,
      signatureValid: true,
    );
  }

  @override
  Future<String> attachmentFile(ChatMessage message) async {
    final attachment = message.attachment;
    if (attachment == null) throw StateError('У сообщения нет вложения');
    final file = await ChatMediaCache.fileFor(message);
    if (await file.exists() && await file.length() > 0) return file.path;

    final downloaded = await _client.storage
        .from(_bucket)
        .download(attachment.path);
    final key = attachment.key;
    final bytes = key == null
        ? downloaded
        : await ChatCryptoService.decryptFile(downloaded, key);
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// Запись сообщения. Личный диалог — всё содержимое внутри шифротекста:
  /// текст как есть (так пишутся сообщения с первой версии), а для вложений и
  /// стикеров — JSON-конверт с типом, подписью и описанием файла вместе с
  /// ключом. Группа — открытые body и media, ключа у файла нет.
  Future<void> _insert({
    required String id,
    required String conversationId,
    required MessageKind kind,
    String? text,
    ChatAttachment? attachment,
  }) async {
    final crypto = await _ready;
    final row = <String, Object?>{
      'id': id,
      'conversation_id': conversationId,
      'sender_id': currentUserId,
      'kind': kind.wire,
    };

    if (await _kind(conversationId) != ConversationKind.direct) {
      row['body'] = text;
      if (attachment != null) row['media'] = attachment.toJson(withKey: false);
    } else {
      final peerId = await _peerId(conversationId);
      final keys = await _loadPublicKeys(peerId);
      if (keys == null) {
        throw StateError('Собеседник ещё не опубликовал ключи шифрования');
      }
      final clear = kind == MessageKind.text
          ? text ?? ''
          : jsonEncode({
              'v': 1,
              'kind': kind.wire,
              'text': ?text,
              'a': ?attachment?.toJson(),
            });
      final payload = await crypto.encrypt(
        conversationId: conversationId,
        messageId: id,
        senderId: currentUserId,
        recipientExchangeKey: keys.exchangeKey,
        text: clear,
      );
      // sent_at проставляет сервер (0030).
      row.addAll({
        'ciphertext': payload.ciphertext,
        'nonce': payload.nonce,
        'mac': payload.mac,
        'signature': payload.signature,
        'protocol_version': ChatCryptoService.protocolVersion,
      });
    }
    await _client.from('chat_messages').insert(row);
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
    final keys = await _loadPublicKeys(await _peerId(conversationId));
    if (keys == null) return 'Ключи собеседника ещё не получены';
    return crypto.securityCode(
      conversationId: conversationId,
      peerExchangeKey: keys.exchangeKey,
    );
  }

  @override
  Future<String> openDirect(String peerId) async {
    await _ready;
    final id = await _client.rpc(
      'create_direct_conversation',
      params: {'in_peer': peerId},
    ) as String;
    _kinds[id] = ConversationKind.direct;
    return id;
  }

  @override
  Future<String> createGroup({
    required String title,
    required List<String> memberIds,
  }) async {
    await _ready;
    final id = await _client.rpc(
      'create_group_chat',
      params: {'in_title': title.trim(), 'in_members': memberIds},
    ) as String;
    _kinds[id] = ConversationKind.group;
    return id;
  }

  @override
  Future<List<ChatMember>> loadMembers(String conversationId) async {
    final rows = await _client
        .from('chat_members')
        .select(
          'profile_id, role, '
          'profiles!chat_members_profile_id_fkey(display_name, avatar_url)',
        )
        .eq('conversation_id', conversationId)
        .order('joined_at');
    return [
      for (final row in rows)
        ChatMember(
          id: row['profile_id'] as String,
          name:
              (row['profiles'] as Map?)?['display_name'] as String? ??
              'Участник',
          avatarUrl: (row['profiles'] as Map?)?['avatar_url'] as String?,
          isOwner: row['role'] == 'owner',
        ),
    ];
  }

  @override
  Future<void> addMembers(String conversationId, List<String> memberIds) =>
      _client.rpc(
        'add_chat_members',
        params: {'in_conversation': conversationId, 'in_members': memberIds},
      );

  @override
  Future<void> removeMember(String conversationId, String memberId) =>
      _client.rpc(
        'remove_chat_member',
        params: {'in_conversation': conversationId, 'in_profile': memberId},
      );

  @override
  Future<void> renameGroup(String conversationId, String title) => _client.rpc(
    'rename_group_chat',
    params: {'in_conversation': conversationId, 'in_title': title.trim()},
  );

  Future<ChatMessage> _decodeDirect({
    required Map<String, dynamic> row,
    required String conversationId,
    required ChatPublicKeys peerKeys,
    required DateTime? peerLastReadAt,
  }) async {
    final crypto = await _ready;
    final myKeys = await crypto.publicKeys;
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
      final clear = decrypted.text;
      var kind = MessageKind.text;
      var text = clear ?? 'Сообщение не прошло проверку подписи';
      ChatAttachment? attachment;
      // Тип берём из зашифрованного конверта, а не из открытой колонки kind:
      // её мог подменить сервер.
      if (clear != null && MessageKind.parse(row['kind']) != MessageKind.text) {
        final envelope = jsonDecode(clear) as Map<String, dynamic>;
        kind = MessageKind.parse(envelope['kind']);
        text = envelope['text'] as String? ?? '';
        attachment = ChatAttachment.fromJson(envelope['a']);
      }
      return ChatMessage(
        id: row['id'] as String,
        conversationId: conversationId,
        senderId: senderId,
        sentAt: sentAt,
        kind: kind,
        text: text,
        attachment: attachment,
        status: _status(sentAt, peerLastReadAt),
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

  Future<String> _peerId(String conversationId) async {
    final row = await _client
        .from('chat_members')
        .select('profile_id')
        .eq('conversation_id', conversationId)
        .neq('profile_id', currentUserId)
        .limit(1)
        .maybeSingle();
    if (row == null) throw StateError('Собеседник не найден');
    return row['profile_id'] as String;
  }

  Future<DateTime?> _peerLastReadAt(String conversationId) async {
    final row = await _client
        .from('chat_members')
        .select('last_read_at')
        .eq('conversation_id', conversationId)
        .neq('profile_id', currentUserId)
        .limit(1)
        .maybeSingle();
    return _date(row?['last_read_at']);
  }

  Future<ChatPublicKeys?> _loadPublicKeys(String profileId) async {
    final cached = _keys[profileId];
    if (cached != null) return cached;
    final row = await _client
        .from('chat_public_keys')
        .select('x25519_public_key, ed25519_public_key, protocol_version')
        .eq('profile_id', profileId)
        .maybeSingle();
    if (row == null ||
        row['protocol_version'] != ChatCryptoService.protocolVersion) {
      return null;
    }
    return _keys[profileId] = ChatPublicKeys(
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
