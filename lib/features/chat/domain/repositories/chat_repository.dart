import '../entities/chat_message.dart';
import '../entities/conversation.dart';

/// Шифрование живёт за этим интерфейсом, в data-слое.
///
/// Наружу отдаётся уже расшифрованный текст, внутрь принимается открытый —
/// презентация не знает ни про ключи, ни про транспорт. Личные диалоги
/// шифруются (X25519 + ChaCha20-Poly1305 + Ed25519, как в DDChat), группы —
/// нет; какой путь выбрать, решает реализация по типу чата.
abstract interface class ChatRepository {
  bool get endToEndEncryptionEnabled;

  Future<List<Conversation>> loadConversations();

  /// Карточка одного чата — для заголовка и прав на экране переписки.
  Future<Conversation> loadConversation(String conversationId);

  /// Поток сообщений одного чата: история плюс входящие в реальном времени.
  Stream<List<ChatMessage>> watchMessages(String conversationId);

  Future<ChatMessage> send({
    required String conversationId,
    required String text,
  });

  Future<void> markRead(String conversationId);

  /// Отпечаток общего секрета — то, что собеседники сверяют голосом,
  /// чтобы исключить подмену ключей посередине. Только для личных диалогов.
  Future<String> securityCode(String conversationId);

  /// Личный диалог с человеком: существующий или новый. Возвращает id чата.
  Future<String> openDirect(String peerId);

  Future<String> createGroup({
    required String title,
    required List<String> memberIds,
  });

  Future<List<ChatMember>> loadMembers(String conversationId);

  Future<void> addMembers(String conversationId, List<String> memberIds);

  /// Исключить участника (владелец) или выйти самому (любой).
  Future<void> removeMember(String conversationId, String memberId);

  Future<void> renameGroup(String conversationId, String title);
}
