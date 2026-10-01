import 'chat_message.dart';

/// На какое сообщение отвечаем. Цитата едет внутри самого сообщения, а не
/// ссылкой: получателю не нужно искать оригинал (он мог уйти за пределы
/// истории или быть удалён), а в личных диалогах цитата зашифрована вместе
/// с текстом.
class ChatReply {
  const ChatReply({
    required this.messageId,
    required this.senderName,
    required this.preview,
    this.kind = MessageKind.text,
  });

  /// Сколько символов цитаты берём: хватает, чтобы узнать сообщение.
  static const previewLength = 140;

  final String messageId;
  final String senderName;
  final String preview;
  final MessageKind kind;

  factory ChatReply.of(ChatMessage message, {required String senderName}) {
    final text = message.text?.trim() ?? '';
    final base = text.isNotEmpty ? text : message.kind.preview;
    return ChatReply(
      messageId: message.id,
      senderName: senderName,
      preview: base.length > previewLength
          ? '${base.substring(0, previewLength)}…'
          : base,
      kind: message.kind,
    );
  }

  Map<String, Object?> toJson() => {
    'id': messageId,
    'n': senderName,
    't': preview,
    if (kind != MessageKind.text) 'k': kind.wire,
  };

  static ChatReply? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    if (id is! String) return null;
    return ChatReply(
      messageId: id,
      senderName: raw['n'] as String? ?? '',
      preview: raw['t'] as String? ?? '',
      kind: MessageKind.parse(raw['k']),
    );
  }
}

/// Служебное содержимое сообщения: ответ и пересылка. В группах лежит в
/// открытой колонке `meta`, в личных диалогах — внутри шифротекста.
class ChatMeta {
  const ChatMeta({this.reply, this.forwardedFrom});

  static const empty = ChatMeta();

  final ChatReply? reply;

  /// Имя автора оригинала. Пересланное пересылкой не «перезаписывается»:
  /// остаётся первый автор, как в Telegram.
  final String? forwardedFrom;

  bool get isEmpty => reply == null && forwardedFrom == null;

  Map<String, Object?> toJson() => {
    if (reply != null) 'r': reply!.toJson(),
    if (forwardedFrom != null) 'f': forwardedFrom,
  };

  static ChatMeta fromJson(Object? raw) {
    if (raw is! Map) return empty;
    final forwarded = raw['f'];
    return ChatMeta(
      reply: ChatReply.fromJson(raw['r']),
      forwardedFrom: forwarded is String && forwarded.isNotEmpty
          ? forwarded
          : null,
    );
  }
}

/// Как отправить: с ответом, пересылкой, без звука.
class SendOptions {
  const SendOptions({this.replyTo, this.forwardedFrom, this.silent = false});

  static const none = SendOptions();

  final ChatReply? replyTo;
  final String? forwardedFrom;

  /// Без звука: сообщение обычное, но у получателя пуш приходит тихим.
  /// Флаг открытый (сервер должен выбрать канал уведомления) — это не
  /// содержимое, а настройка доставки.
  final bool silent;

  ChatMeta get meta => ChatMeta(reply: replyTo, forwardedFrom: forwardedFrom);
}

/// Отложенное сообщение: лежит на сервере и уходит в [sendAt] либо когда
/// собеседник появится в сети ([whenOnline]).
class ScheduledMessage {
  const ScheduledMessage({
    required this.id,
    required this.conversationId,
    required this.text,
    required this.createdAt,
    this.sendAt,
    this.whenOnline = false,
    this.silent = false,
  });

  final String id;
  final String conversationId;
  final String text;
  final DateTime createdAt;
  final DateTime? sendAt;
  final bool whenOnline;
  final bool silent;
}
