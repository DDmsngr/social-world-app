import '../stickers.dart';
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
    this.thumbUrl,
    this.thumbB64,
  });

  /// Картинка-превью в цитате (например, кадр истории, на которую отвечают).
  final String? thumbUrl;

  /// Крошечное превью фото/видео, зашитое в саму цитату (base64).
  final String? thumbB64;

  ChatReply withThumb(String? b64) => ChatReply(
    messageId: messageId,
    senderName: senderName,
    preview: preview,
    kind: kind,
    thumbUrl: thumbUrl,
    thumbB64: b64 ?? thumbB64,
  );

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
    if (thumbUrl != null) 'u': thumbUrl,
    if (thumbB64 != null) 'b': thumbB64,
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
      thumbB64: raw['b'] is String && (raw['b'] as String).length < 40000
          ? raw['b'] as String
          : null,
      thumbUrl: switch (raw['u']) {
        final String url when url.startsWith('https://') => url,
        _ => null,
      },
    );
  }
}

/// Служебное содержимое сообщения: ответ, пересылка, id стикера. В группах
/// лежит в открытой колонке `meta`, в личных диалогах — внутри шифротекста.
class ChatMeta {
  const ChatMeta({
    this.reply,
    this.forwardedFrom,
    this.linkPreview,
    this.sticker,
    this.emoji = const [],
  });

  static const empty = ChatMeta();

  final ChatReply? reply;

  /// Имя автора оригинала. Пересланное пересылкой не «перезаписывается»:
  /// остаётся первый автор, как в Telegram.
  final String? forwardedFrom;

  /// Карточка ссылки из текста. Страницу открывал телефон отправителя, а не
  /// получателя: чужие сайты не узнают, кто читает сообщение.
  final LinkPreview? linkPreview;

  /// Id фирменного стикера (`<пак>.<ключ>`). Текст такого сообщения —
  /// эмодзи-заменитель: его и покажут версии, которые стикеров не знают.
  final String? sticker;

  /// Свои эмодзи внутри текста (см. [CustomEmoji]).
  final List<CustomEmoji> emoji;

  bool get isEmpty =>
      reply == null &&
      forwardedFrom == null &&
      linkPreview == null &&
      sticker == null &&
      emoji.isEmpty;

  Map<String, Object?> toJson() => {
    if (reply != null) 'r': reply!.toJson(),
    if (forwardedFrom != null) 'f': forwardedFrom,
    if (linkPreview != null) 'l': linkPreview!.toJson(),
    if (sticker != null) 's': sticker,
    if (emoji.isNotEmpty) 'e': [for (final e in emoji) e.toJson()],
  };

  static ChatMeta fromJson(Object? raw) {
    if (raw is! Map) return empty;
    final forwarded = raw['f'];
    final sticker = raw['s'];
    final emoji = raw['e'];
    return ChatMeta(
      reply: ChatReply.fromJson(raw['r']),
      forwardedFrom: forwarded is String && forwarded.isNotEmpty
          ? forwarded
          : null,
      linkPreview: LinkPreview.fromJson(raw['l']),
      sticker: sticker is String && sticker.isNotEmpty ? sticker : null,
      emoji: emoji is List
          ? [for (final e in emoji.take(200)) ?CustomEmoji.fromJson(e)]
          : const [],
    );
  }
}

/// Превью ссылки: заголовок, описание и маленькая картинка (base64).
class LinkPreview {
  const LinkPreview({required this.url, this.title, this.description, this.imageB64});

  final String url;
  final String? title;
  final String? description;
  final String? imageB64;

  bool get hasContent => (title?.isNotEmpty ?? false) || (description?.isNotEmpty ?? false);

  Map<String, Object?> toJson() => {
    'u': url,
    if (title != null) 't': title,
    if (description != null) 'd': description,
    if (imageB64 != null) 'i': imageB64,
  };

  static LinkPreview? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final url = raw['u'];
    if (url is! String || !url.startsWith('http')) return null;
    final image = raw['i'];
    return LinkPreview(
      url: url,
      title: raw['t'] as String?,
      description: raw['d'] as String?,
      imageB64: image is String && image.length < 40000 ? image : null,
    );
  }
}

/// Как отправить: с ответом, пересылкой, без звука, стикером.
class SendOptions {
  const SendOptions({
    this.replyTo,
    this.forwardedFrom,
    this.silent = false,
    this.linkPreview,
    this.sticker,
    this.customEmoji = const [],
  });

  static const none = SendOptions();

  final ChatReply? replyTo;
  final String? forwardedFrom;
  final LinkPreview? linkPreview;

  /// Id стикера для сообщения с [MessageKind.sticker].
  final String? sticker;

  /// Свои эмодзи внутри текста.
  final List<CustomEmoji> customEmoji;

  /// Без звука: сообщение обычное, но у получателя пуш приходит тихим.
  /// Флаг открытый (сервер должен выбрать канал уведомления) — это не
  /// содержимое, а настройка доставки.
  final bool silent;

  ChatMeta get meta =>
      ChatMeta(
        reply: replyTo,
        forwardedFrom: forwardedFrom,
        linkPreview: linkPreview,
        sticker: sticker,
        emoji: customEmoji,
      );
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
