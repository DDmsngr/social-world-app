import '../entities/chat_message.dart';
import '../entities/conversation.dart';

/// Шифрование живёт за этим интерфейсом, в data-слое.
///
/// Наружу отдаётся уже расшифрованный текст, внутрь принимается открытый —
/// презентация не знает ни про ключи, ни про транспорт. Так реализацию можно
/// заменить с заглушки на боевую (X25519 + ChaCha20-Poly1305 + Ed25519,
/// как в DDChat) не трогая ни одного экрана.
abstract interface class ChatRepository {
  Future<List<Conversation>> loadConversations();

  /// Поток сообщений одного диалога: история плюс входящие в реальном времени.
  Stream<List<ChatMessage>> watchMessages(String conversationId);

  Future<ChatMessage> send({
    required String conversationId,
    required String text,
  });

  Future<void> markRead(String conversationId);

  /// Отпечаток общего секрета — то, что собеседники сверяют голосом,
  /// чтобы исключить подмену ключей посередине.
  Future<String> securityCode(String conversationId);
}
