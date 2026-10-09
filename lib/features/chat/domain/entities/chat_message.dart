import '../stickers.dart';
import 'chat_meta.dart';

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
    this.album = const [],
  });

  final String path;
  final int size;
  final String? name;
  final String? mime;
  final int? durationMs;

  /// Громкость голосового по столбикам 0..1 — рисуется волной.
  final List<double>? waveform;
  final String? key;

  /// Остальные файлы альбома (пост канала из нескольких фото). Первый файл —
  /// само это вложение.
  final List<ChatAttachment> album;

  /// Все файлы по порядку: это вложение и альбом за ним.
  List<ChatAttachment> get all => [this, ...album];

  Map<String, Object?> toJson({bool withKey = true}) => {
    'path': path,
    'size': size,
    if (name != null) 'name': name,
    if (mime != null) 'mime': mime,
    if (durationMs != null) 'duration_ms': durationMs,
    if (waveform != null)
      'waveform': [for (final v in waveform!) double.parse(v.toStringAsFixed(2))],
    if (withKey && key != null) 'key': key,
    if (album.isNotEmpty) 'album': [for (final a in album) a.toJson(withKey: withKey)],
  };

  static ChatAttachment? fromJson(Object? raw, {bool nested = false}) {
    if (raw is! Map) return null;
    final path = raw['path'];
    if (path is! String) return null;
    final album = raw['album'];
    return ChatAttachment(
      album: nested || album is! List
          ? const []
          : [
              for (final item in album) ?ChatAttachment.fromJson(item, nested: true),
            ],
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
    this.replyTo,
    this.forwardedFrom,
    this.editedAt,
    this.stickerId,
    this.customEmoji = const [],
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

  /// Цитата сообщения, на которое это — ответ.
  final ChatReply? replyTo;

  /// Автор оригинала, если сообщение переслано.
  final String? forwardedFrom;

  /// Когда автор последний раз правил текст; null — не правил.
  final DateTime? editedAt;

  /// Id фирменного стикера; [text] у такого сообщения — эмодзи-заменитель.
  final String? stickerId;

  /// Свои эмодзи внутри [text]; на их местах в тексте — обычные эмодзи.
  final List<CustomEmoji> customEmoji;

  /// Строка для списка чатов.
  String get preview {
    // Посты каналов приходят с Markdown — в списке чатов разметка не нужна.
    final caption = text
        ?.replaceAllMapped(RegExp(r'\[([^\]]*)\]\([^)]*\)'), (m) => m[1]!)
        .replaceAll(RegExp(r'[*`~]|^#+\s*', multiLine: true), '')
        .replaceAll(RegExp(r'\s*\n\s*'), ' ')
        .trim();
    if (kind == MessageKind.text || kind == MessageKind.sticker) {
      return caption?.isNotEmpty == true ? caption! : kind.preview;
    }
    final label = kind == MessageKind.image && (attachment?.album.isNotEmpty ?? false)
        ? '📷 Фото (${attachment!.all.length})'
        : kind.preview;
    return caption?.isNotEmpty == true ? '$label · $caption' : label;
  }

  ChatMessage copyWith({
    MessageStatus? status,
    bool? signatureValid,
    String? text,
    DateTime? editedAt,
  }) =>
      ChatMessage(
        id: id,
        conversationId: conversationId,
        senderId: senderId,
        sentAt: sentAt,
        kind: kind,
        text: text ?? this.text,
        attachment: attachment,
        status: status ?? this.status,
        signatureValid: signatureValid ?? this.signatureValid,
        senderName: senderName,
        replyTo: replyTo,
        forwardedFrom: forwardedFrom,
        editedAt: editedAt ?? this.editedAt,
        stickerId: stickerId,
        customEmoji: customEmoji,
      );
}
