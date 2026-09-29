import 'chat_message.dart';

/// direct — личный диалог со сквозным шифрованием; group — группа без E2EE,
/// созданная людьми; quest — чат квеста, состав ведёт сервер.
enum ConversationKind {
  direct,
  group,
  quest;

  static ConversationKind parse(Object? raw) => switch (raw) {
    'group' => ConversationKind.group,
    'quest' => ConversationKind.quest,
    _ => ConversationKind.direct,
  };
}

class Conversation {
  const Conversation({
    required this.id,
    this.kind = ConversationKind.direct,
    this.peerId,
    this.peerName,
    this.peerAvatarUrl,
    this.title,
    this.memberCount = 2,
    this.isOwner = false,
    this.closed = false,
    this.lastMessage,
    this.unreadCount = 0,
    this.online = false,
    this.encrypted = true,
  });

  final String id;
  final ConversationKind kind;

  /// Собеседник — только у личного диалога.
  final String? peerId;
  final String? peerName;
  final String? peerAvatarUrl;

  /// Название группы или квеста.
  final String? title;
  final int memberCount;

  /// Владелец группы может переименовать её и исключать участников.
  final bool isOwner;

  /// Закрытый чат (завершённый квест) только читается.
  final bool closed;
  final ChatMessage? lastMessage;
  final int unreadCount;
  final bool online;

  /// Ключи согласованы и переписка шифруется. У групп всегда false: там
  /// шифрования нет намеренно, и интерфейс это показывает.
  final bool encrypted;

  bool get isDirect => kind == ConversationKind.direct;

  /// Управлять составом можно только в группе, которую создали люди.
  bool get isGroup => kind == ConversationKind.group;

  String get displayName =>
      (isDirect ? peerName : title) ?? (isDirect ? 'Пользователь' : 'Группа');

  Conversation copyWith({ChatMessage? lastMessage, int? unreadCount}) =>
      Conversation(
        id: id,
        kind: kind,
        peerId: peerId,
        peerName: peerName,
        peerAvatarUrl: peerAvatarUrl,
        title: title,
        memberCount: memberCount,
        isOwner: isOwner,
        closed: closed,
        lastMessage: lastMessage ?? this.lastMessage,
        unreadCount: unreadCount ?? this.unreadCount,
        online: online,
        encrypted: encrypted,
      );
}

/// Участник группового чата.
class ChatMember {
  const ChatMember({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.isOwner = false,
  });

  final String id;
  final String name;
  final String? avatarUrl;
  final bool isOwner;
}
