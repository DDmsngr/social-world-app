import 'dart:async';

import '../domain/entities/chat_message.dart';
import '../domain/entities/conversation.dart';
import '../domain/repositories/chat_repository.dart';

/// Заглушка до подключения транспорта и крипто.
///
/// Шифрования здесь нет и не изображается: [securityCode] возвращает пометку
/// вместо отпечатка, чтобы в интерфейсе было честно видно, что переписка пока
/// не защищена. Боевая реализация появится отдельным классом рядом.
class LocalChatRepository implements ChatRepository {
  LocalChatRepository({required this.currentUserId});

  final String Function() currentUserId;

  final _controllers = <String, StreamController<List<ChatMessage>>>{};
  late final Map<String, List<ChatMessage>> _messages = {
    for (final conversation in _seedConversations)
      conversation.id: _seedMessages(conversation, currentUserId()),
  };
  late final List<Conversation> _conversations = List.of(_seedConversations);
  var _nextId = 0;

  @override
  bool get endToEndEncryptionEnabled => false;

  @override
  Future<List<Conversation>> loadConversations() async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    return List.unmodifiable(_conversations);
  }

  @override
  Stream<List<ChatMessage>> watchMessages(String conversationId) {
    final controller = _controllers.putIfAbsent(
      conversationId,
      () => StreamController<List<ChatMessage>>.broadcast(),
    );
    return Stream.multi((listener) {
      listener.add(List.unmodifiable(_messages[conversationId] ?? const []));
      final subscription = controller.stream.listen(listener.add);
      listener.onCancel = subscription.cancel;
    });
  }

  @override
  Future<ChatMessage> send({
    required String conversationId,
    required String text,
  }) async {
    final message = ChatMessage(
      id: 'local-msg-${_nextId++}',
      conversationId: conversationId,
      senderId: currentUserId(),
      sentAt: DateTime.now(),
      text: text.trim(),
      status: MessageStatus.sent,
      signatureValid: true,
    );

    final thread = _messages.putIfAbsent(conversationId, () => []);
    thread.add(message);
    _controllers[conversationId]?.add(List.unmodifiable(thread));

    final index = _conversations.indexWhere((c) => c.id == conversationId);
    if (index != -1) {
      _conversations[index] = _conversations[index].copyWith(
        lastMessage: message,
      );
    }
    return message;
  }

  @override
  Future<void> markRead(String conversationId) async {
    final index = _conversations.indexWhere((c) => c.id == conversationId);
    if (index != -1) {
      _conversations[index] = _conversations[index].copyWith(unreadCount: 0);
    }
  }

  @override
  Future<String> securityCode(String conversationId) async =>
      'Переписка ещё не шифруется';

  void dispose() {
    for (final controller in _controllers.values) {
      controller.close();
    }
  }

  static final _seedConversations = <Conversation>[
    Conversation(
      id: 'conv-1',
      peerId: 'person-1',
      peerName: 'Алина',
      online: true,
      unreadCount: 2,
      encrypted: false,
    ),
    Conversation(
      id: 'conv-2',
      peerId: 'person-3',
      peerName: 'Саша',
      encrypted: false,
    ),
    Conversation(
      id: 'conv-3',
      peerId: 'person-6',
      peerName: 'Ника',
      unreadCount: 1,
      encrypted: false,
    ),
  ];

  static List<ChatMessage> _seedMessages(Conversation conversation, String me) {
    final now = DateTime.now();
    final lines = switch (conversation.id) {
      'conv-1' => [
        ('person-1', 'Привет! Видела твой пост про набережную', 42),
        (me, 'Привет. Да, вчера ходили, красиво', 38),
        ('person-1', 'Завтра собираемся там же часов в семь, придёшь?', 4),
      ],
      'conv-2' => [
        ('person-3', 'Забег в семь от Театральной, ты с нами?', 180),
        (me, 'Постараюсь, зависит от работы', 176),
      ],
      _ => [('person-6', 'Кофе у Площади Искусств правда хороший', 25)],
    };

    return [
      for (final (index, line) in lines.indexed)
        ChatMessage(
          id: '${conversation.id}-$index',
          conversationId: conversation.id,
          senderId: line.$1,
          sentAt: now.subtract(Duration(minutes: line.$3)),
          text: line.$2,
          status: MessageStatus.read,
        ),
    ];
  }
}
