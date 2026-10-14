import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/chat/data/crypto/chat_crypto_service.dart';
import '../../features/chat/data/crypto/chat_key_storage.dart';
import '../../features/chat/data/message_envelope.dart';
import '../../features/chat/domain/entities/chat_message.dart';

/// Текст личного сообщения для шторки. Сервер текста не знает (сквозное
/// шифрование) и шлёт «Новое сообщение» с id сообщения; телефон получателя
/// сам достаёт строку, расшифровывает своим ключом и подменяет уведомление.
///
/// null — показать нечего (нет сессии или ключей, сообщение не нашлось или
/// не расшифровалось): тогда в шторке остаётся «Новое сообщение».
Future<String?> directMessagePreview(
  Map<String, dynamic> data, {
  SupabaseClient? client,
  ChatKeyStorage? keyStorage,
}) async {
  if (data['type'] != 'message' || data['e2e'] != '1') return null;
  final messageId = data['message_id'];
  final conversationId = data['conversation_id'];
  if (messageId is! String || conversationId is! String) return null;

  final db = client ?? Supabase.instance.client;
  final me = db.auth.currentUser?.id;
  if (me == null) return null;
  final storage = keyStorage ?? SecureChatKeyStorage();
  // Без своих ключей не расшифровать. Создавать их здесь нельзя: новые ключи
  // не опубликованы, и переписка на этом телефоне сломалась бы.
  if (!await ChatCryptoService.hasKeys(userId: me, storage: storage)) return null;

  const timeout = Duration(seconds: 8);
  final row = await db
      .from('chat_messages')
      .select('id, conversation_id, sender_id, kind, ciphertext, nonce, mac, signature')
      .eq('id', messageId)
      .maybeSingle()
      .timeout(timeout);
  if (row == null || row['conversation_id'] != conversationId || row['ciphertext'] == null) return null;
  final senderId = row['sender_id'] as String;
  if (senderId == me) return null;

  final keys = await db
      .from('chat_public_keys')
      .select('x25519_public_key, ed25519_public_key')
      .eq('profile_id', senderId)
      .maybeSingle()
      .timeout(timeout);
  if (keys == null) return null;

  final crypto = await ChatCryptoService.initialize(userId: me, storage: storage);
  final decrypted = await crypto.decrypt(
    conversationId: conversationId,
    messageId: messageId,
    senderId: senderId,
    peerExchangeKey: keys['x25519_public_key'] as String,
    senderSigningKey: keys['ed25519_public_key'] as String,
    payload: EncryptedChatPayload(
      ciphertext: row['ciphertext'] as String,
      nonce: row['nonce'] as String,
      mac: row['mac'] as String,
      signature: row['signature'] as String,
    ),
  );
  final clear = decrypted.text;
  if (clear == null) return null;
  final envelope = MessageEnvelope.decode(clear, rowKind: MessageKind.parse(row['kind']));
  final message = ChatMessage(
    id: messageId,
    conversationId: conversationId,
    senderId: senderId,
    sentAt: DateTime.now(),
    kind: envelope.kind,
    text: envelope.text,
    attachment: envelope.attachment,
  );
  final preview = message.preview;
  return preview.length > 300 ? '${preview.substring(0, 300)}…' : preview;
}
