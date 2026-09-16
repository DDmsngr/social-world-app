enum MessageKind { text, image, voice, file }

/// Доставка считается от отправителя: sending → sent → delivered → read.
enum MessageStatus { sending, sent, delivered, read, failed }

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.sentAt,
    this.kind = MessageKind.text,
    this.text,
    this.mediaUrl,
    this.status = MessageStatus.sent,
    this.signatureValid,
  });

  final String id;
  final String conversationId;
  final String senderId;
  final DateTime sentAt;
  final MessageKind kind;

  /// Уже расшифрованный текст. В хранилище и на сервере лежит шифротекст —
  /// расшифровка происходит в data-слое, презентация про ключи не знает.
  final String? text;

  final String? mediaUrl;
  final MessageStatus status;

  /// Проверка подписи отправителя. null — пока не проверялась.
  /// false показывается в интерфейсе явно: подделанное сообщение нельзя
  /// молча выдавать за обычное.
  final bool? signatureValid;

  ChatMessage copyWith({MessageStatus? status, bool? signatureValid}) =>
      ChatMessage(
        id: id,
        conversationId: conversationId,
        senderId: senderId,
        sentAt: sentAt,
        kind: kind,
        text: text,
        mediaUrl: mediaUrl,
        status: status ?? this.status,
        signatureValid: signatureValid ?? this.signatureValid,
      );
}
