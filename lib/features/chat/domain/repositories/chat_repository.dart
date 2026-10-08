import '../entities/chat_message.dart';
import '../entities/chat_meta.dart';
import '../entities/conversation.dart';

/// Шифрование живёт за этим интерфейсом, в data-слое.
///
/// Наружу отдаётся уже расшифрованный текст, внутрь принимается открытый —
/// презентация не знает ни про ключи, ни про транспорт. Личные диалоги
/// шифруются (X25519 + ChaCha20-Poly1305 + Ed25519, как в DDChat), группы —
/// нет; какой путь выбрать, решает реализация по типу чата.
/// Сколько фото помещается в одном сообщении-альбоме.
const maxAlbumPhotos = 8;

abstract interface class ChatRepository {
  bool get endToEndEncryptionEnabled;

  Future<List<Conversation>> loadConversations();

  /// Карточка одного чата — для заголовка и прав на экране переписки.
  Future<Conversation> loadConversation(String conversationId);

  /// Поток сообщений одного чата: история плюс входящие в реальном времени.
  Stream<List<ChatMessage>> watchMessages(String conversationId);

  /// Текст или стикер ([kind] = sticker, [text] — эмодзи).
  Future<ChatMessage> send({
    required String conversationId,
    required String text,
    MessageKind kind = MessageKind.text,
    SendOptions options = SendOptions.none,
  });

  /// Фото, видео, кружок, голосовое или файл. Файл с устройства по [filePath]
  /// загружается в хранилище (в личных диалогах — зашифрованным).
  Future<ChatMessage> sendAttachment({
    required String conversationId,
    required MessageKind kind,
    required String filePath,
    String? name,
    String? mime,
    int? durationMs,
    List<double>? waveform,
    String? caption,
    SendOptions options = SendOptions.none,
  });

  /// Несколько фото одним сообщением (альбом) с общей подписью. От 2 до
  /// [maxAlbumPhotos] файлов; больше — вызывающий делит на группы.
  Future<ChatMessage> sendAlbum({
    required String conversationId,
    required List<String> filePaths,
    String? caption,
    SendOptions options = SendOptions.none,
  });

  /// Отложить текст: уйдёт в [sendAt] либо когда собеседник появится в сети
  /// ([whenOnline], только личные диалоги). Ровно одно из двух. Текст
  /// шифруется сразу — сервер хранит и отдаёт готовый шифротекст.
  Future<ScheduledMessage> scheduleText({
    required String conversationId,
    required String text,
    DateTime? sendAt,
    bool whenOnline = false,
    SendOptions options = SendOptions.none,
  });

  Future<List<ScheduledMessage>> loadScheduled(String conversationId);

  Future<void> cancelScheduled(String id);

  /// Отметка «я в сети» — по ней сервер понимает, что пора отправлять
  /// сообщения «когда будет в сети». Наружу не отдаётся никому.
  Future<void> touchPresence();

  /// Удалить у всех участников. Возвращает id, которые удалось удалить:
  /// своё — всегда, чужое — только владельцу группы. Скрыть «только у
  /// себя» — не сюда, это настройка устройства (hiddenMessagesProvider).
  Future<Set<String>> deleteForEveryone(List<ChatMessage> messages);

  /// Правка своего сообщения: новый текст (или подпись к вложению). Вложение,
  /// цитата и пересылка остаются как были. Возвращает сообщение с пометкой
  /// «изменено».
  Future<ChatMessage> editMessage(ChatMessage message, String text);

  /// Путь к файлу вложения на устройстве: скачивает и расшифровывает при
  /// первом обращении, дальше берёт из кэша.
  Future<String> attachmentFile(ChatMessage message);

  Future<void> markRead(String conversationId);

  /// Сообщения чата по id: для закрепов и закладок. Старые, которых нет в
  /// загруженной ленте, докачиваются и расшифровываются здесь же. Удалённые у
  /// всех в результат не попадают. Порядок — от старых к новым.
  Future<List<ChatMessage>> loadMessagesByIds(
    String conversationId,
    List<String> ids,
  );

  /// Отпечаток общего секрета — то, что собеседники сверяют голосом,
  /// чтобы исключить подмену ключей посередине. Только для личных диалогов.
  Future<String> securityCode(String conversationId);

  /// Ключ собеседника не совпадает с тем, что телефон запомнил при первой
  /// встрече. Пока новый ключ не принят, отправка в диалог не идёт.
  Future<bool> peerKeyChanged(String conversationId);

  /// Принять текущий ключ собеседника (после сверки кода безопасности).
  Future<void> acceptPeerKey(String conversationId);

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

/// Сервер ещё не умеет удалять сообщения (не накатана миграция 0033).
class ChatDeleteUnavailable implements Exception {
  const ChatDeleteUnavailable();

  @override
  String toString() =>
      'Удаление у всех пока недоступно на сервере. Сообщение можно скрыть у себя.';
}

/// Нужная миграция ещё не накатана на сервер.
class ChatFeatureUnavailable implements Exception {
  const ChatFeatureUnavailable();

  @override
  String toString() =>
      'Эта возможность пока недоступна на сервере. Попробуйте позже.';
}
