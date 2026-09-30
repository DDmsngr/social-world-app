/// Тип сообщения. [wire] совпадает с `chat_messages.kind` в базе.
enum MessageKind {
  text,
  image,
  video,
  videoNote('video_note'),
  voice,
  file,
  sticker;

  const MessageKind([this._wire]);

  final String? _wire;

  String get wire => _wire ?? name;

  static MessageKind parse(Object? raw) {
    for (final kind in values) {
      if (kind.wire == raw) return kind;
    }
    return MessageKind.text;
  }

  /// Подпись в списке чатов и в пуше, когда текста нет.
  String get preview => switch (this) {
    MessageKind.text => 'Сообщение',
    MessageKind.image => '📷 Фото',
    MessageKind.video => '🎬 Видео',
    MessageKind.videoNote => '🎥 Видеосообщение',
    MessageKind.voice => '🎤 Голосовое',
    MessageKind.file => '📎 Файл',
    MessageKind.sticker => 'Стикер',
  };
}

/// Доставка считается от отправителя: sending → sent → delivered → read.
enum MessageStatus { sending, sent, delivered, read, failed }

/// Файл сообщения в хранилище `chat-media`. В личных диалогах файл
/// зашифрован, и [key] — его ключ; он приходит только внутри зашифрованного
/// сообщения и на сервере в открытом виде не лежит.
class ChatAttachment {
  const ChatAttachment({
    required this.path,
    required this.size,
    this.name,
    this.mime,
    this.durationMs,
    this.waveform,
    this.key,
  });

  final String path;
  final int size;
  final String? name;
  final String? mime;
  final int? durationMs;

  /// Громкость голосового по столбикам 0..1 — рисуется волной.
  final List<double>? waveform;
  final String? key;

  Map<String, Object?> toJson({bool withKey = true}) => {
    'path': path,
    'size': size,
    if (name != null) 'name': name,
    if (mime != null) 'mime': mime,
    if (durationMs != null) 'duration_ms': durationMs,
    if (waveform != null)
      'waveform': [for (final v in waveform!) double.parse(v.toStringAsFixed(2))],
    if (withKey && key != null) 'key': key,
  };

  static ChatAttachment? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final path = raw['path'];
    if (path is! String) return null;
    return ChatAttachment(
      path: path,
      size: (raw['size'] as num?)?.toInt() ?? 0,
      name: raw['name'] as String?,
      mime: raw['mime'] as String?,
      durationMs: (raw['duration_ms'] as num?)?.toInt(),
      waveform: (raw['waveform'] as List?)
          ?.map((v) => (v as num).toDouble().clamp(0.0, 1.0))
          .toList(),
      key: raw['key'] as String?,
    );
  }
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.sentAt,
    this.kind = MessageKind.text,
    this.text,
    this.attachment,
    this.status = MessageStatus.sent,
    this.signatureValid,
    this.senderName,
  });

  final String id;
  final String conversationId;
  final String senderId;
  final DateTime sentAt;
  final MessageKind kind;

  /// Уже расшифрованный текст: само сообщение, подпись к вложению или эмодзи
  /// стикера. На сервере у личных диалогов лежит шифротекст — расшифровка
  /// происходит в data-слое, презентация про ключи не знает.
  final String? text;

  final ChatAttachment? attachment;
  final MessageStatus status;

  /// Проверка подписи отправителя. null — пока не проверялась.
  /// false показывается в интерфейсе явно: подделанное сообщение нельзя
  /// молча выдавать за обычное.
  final bool? signatureValid;

  /// Имя автора — показывается в группах над чужими сообщениями.
  final String? senderName;

  /// Строка для списка чатов.
  String get preview {
    final caption = text?.trim();
    if (kind == MessageKind.text || kind == MessageKind.sticker) {
      return caption?.isNotEmpty == true ? caption! : kind.preview;
    }
    return caption?.isNotEmpty == true
        ? '${kind.preview} · $caption'
        : kind.preview;
  }

  ChatMessage copyWith({MessageStatus? status, bool? signatureValid}) =>
      ChatMessage(
        id: id,
        conversationId: conversationId,
        senderId: senderId,
        sentAt: sentAt,
        kind: kind,
        text: text,
        attachment: attachment,
        status: status ?? this.status,
        signatureValid: signatureValid ?? this.signatureValid,
        senderName: senderName,
      );
}
