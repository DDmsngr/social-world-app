import 'chat_message.dart';

class Conversation {
  const Conversation({
    required this.id,
    required this.peerId,
    required this.peerName,
    this.peerAvatarUrl,
    this.lastMessage,
    this.unreadCount = 0,
    this.online = false,
    this.encrypted = true,
  });

  final String id;
  final String peerId;
  final String peerName;
  final String? peerAvatarUrl;
  final ChatMessage? lastMessage;
  final int unreadCount;
  final bool online;

  /// Ключи согласованы и переписка шифруется. Пока общий секрет не установлен,
  /// в интерфейсе это видно, а отправка не притворяется защищённой.
  final bool encrypted;

  Conversation copyWith({ChatMessage? lastMessage, int? unreadCount}) =>
      Conversation(
        id: id,
        peerId: peerId,
        peerName: peerName,
        peerAvatarUrl: peerAvatarUrl,
        lastMessage: lastMessage ?? this.lastMessage,
        unreadCount: unreadCount ?? this.unreadCount,
        online: online,
        encrypted: encrypted,
      );
}
