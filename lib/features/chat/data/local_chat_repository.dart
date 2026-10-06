import 'dart:async';

import '../domain/entities/chat_message.dart';
import '../domain/entities/chat_meta.dart';
import '../domain/entities/conversation.dart';
import '../domain/repositories/chat_repository.dart';

/// Заглушка для режима без бэкенда (веб-прогоны, тесты).
///
/// Шифрования здесь нет и не изображается: [securityCode] возвращает пометку
/// вместо отпечатка, чтобы в интерфейсе было честно видно, что переписка
/// не защищена.
class LocalChatRepository implements ChatRepository {
  LocalChatRepository({required this.currentUserId});

  final String Function() currentUserId;

  final _controllers = <String, StreamController<List<ChatMessage>>>{};
  late final Map<String, List<ChatMessage>> _messages = {
    for (final conversation in _seedConversations)
      conversation.id: _seedMessages(conversation, currentUserId()),
  };
  late final List<Conversation> _conversations = List.of(_seedConversations);
  final _members = <String, List<ChatMember>>{};
  var _nextId = 0;

  static const _people = <String, String>{
    'person-1': 'Алина',
    'person-2': 'Марк',
    'person-3': 'Саша',
    'person-4': 'Лена',
    'person-5': 'Илья',
    'person-6': 'Ника',
  };

  @override
  bool get endToEndEncryptionEnabled => false;

  @override
  Future<List<Conversation>> loadConversations() async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    return List.unmodifiable(_conversations);
  }

  @override
  Future<Conversation> loadConversation(String conversationId) async =>
      _conversations.firstWhere((c) => c.id == conversationId);

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
    MessageKind kind = MessageKind.text,
    SendOptions options = SendOptions.none,
  }) async => _add(
    ChatMessage(
      id: 'local-msg-${_nextId++}',
      conversationId: conversationId,
      senderId: currentUserId(),
      sentAt: DateTime.now(),
      kind: kind,
      text: text.trim(),
      status: MessageStatus.sent,
      signatureValid: true,
      replyTo: options.replyTo,
      forwardedFrom: options.forwardedFrom,
    ),
  );

  @override
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
  }) async => _add(
    ChatMessage(
      id: 'local-msg-${_nextId++}',
      conversationId: conversationId,
      senderId: currentUserId(),
      sentAt: DateTime.now(),
      kind: kind,
      text: caption,
      // В заглушке «хранилище» — сам файл на устройстве.
      attachment: ChatAttachment(
        path: filePath,
        size: 0,
        name: name,
        mime: mime,
        durationMs: durationMs,
        waveform: waveform,
      ),
      status: MessageStatus.sent,
      signatureValid: true,
      replyTo: options.replyTo,
      forwardedFrom: options.forwardedFrom,
    ),
  );

  /// Отложенные живут в памяти; уходят они только руками (см. [releaseScheduled]).
  final _scheduled = <ScheduledMessage>[];

  @override
  Future<ScheduledMessage> scheduleText({
    required String conversationId,
    required String text,
    DateTime? sendAt,
    bool whenOnline = false,
    SendOptions options = SendOptions.none,
  }) async {
    final message = ScheduledMessage(
      id: 'local-sched-${_nextId++}',
      conversationId: conversationId,
      text: text.trim(),
      createdAt: DateTime.now(),
      sendAt: sendAt,
      whenOnline: whenOnline,
      silent: options.silent,
    );
    _scheduled.add(message);
    return message;
  }

  @override
  Future<List<ScheduledMessage>> loadScheduled(String conversationId) async => [
    for (final m in _scheduled)
      if (m.conversationId == conversationId) m,
  ];

  @override
  Future<void> cancelScheduled(String id) async =>
      _scheduled.removeWhere((m) => m.id == id);

  /// Для тестов и демо: «сервер» отправляет отложенное прямо сейчас.
  Future<void> releaseScheduled(String id) async {
    final index = _scheduled.indexWhere((m) => m.id == id);
    if (index == -1) return;
    final scheduled = _scheduled.removeAt(index);
    await send(
      conversationId: scheduled.conversationId,
      text: scheduled.text,
      options: SendOptions(silent: scheduled.silent),
    );
  }

  @override
  Future<void> touchPresence() async {}

  @override
  Future<String> attachmentFile(ChatMessage message) async =>
      message.attachment?.path ?? (throw StateError('Нет вложения'));

  @override
  Future<ChatMessage> editMessage(ChatMessage message, String text) async {
    if (message.senderId != currentUserId()) {
      throw StateError('Менять можно только свои сообщения');
    }
    final edited = message.copyWith(text: text.trim(), editedAt: DateTime.now());
    final thread = _messages[message.conversationId];
    final index = thread?.indexWhere((m) => m.id == message.id) ?? -1;
    if (thread != null && index >= 0) {
      thread[index] = edited;
      _controllers[message.conversationId]?.add(List.unmodifiable(thread));
    }
    return edited;
  }

  @override
  Future<Set<String>> deleteForEveryone(List<ChatMessage> messages) async {
    final me = currentUserId();
    final deleted = <String>{};
    for (final message in messages) {
      final conversationId = message.conversationId;
      final conversation =
          _conversations.where((c) => c.id == conversationId).firstOrNull;
      // Те же правила, что у delete_chat_messages (0033): своё — всегда,
      // чужое — только владельцу группы.
      final allowed = message.senderId == me ||
          (conversation != null &&
              !conversation.isDirect &&
              conversation.isOwner);
      if (!allowed) continue;
      final thread = _messages[conversationId];
      if (thread == null) continue;
      final before = thread.length;
      thread.removeWhere((m) => m.id == message.id);
      if (thread.length == before) continue;
      deleted.add(message.id);
      _controllers[conversationId]?.add(List.unmodifiable(thread));
      final index = _conversations.indexWhere((c) => c.id == conversationId);
      if (index != -1) {
        _conversations[index] = _conversations[index].copyWith(
          lastMessage: thread.isEmpty ? null : thread.last,
        );
      }
    }
    return deleted;
  }

  ChatMessage _add(ChatMessage message) {
    final conversationId = message.conversationId;
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
  Future<List<ChatMessage>> loadMessagesByIds(
    String conversationId,
    List<String> ids,
  ) async => [
    for (final m in _messages[conversationId] ?? const <ChatMessage>[])
      if (ids.contains(m.id)) m,
  ];

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

  @override
  Future<String> openDirect(String peerId) async {
    for (final c in _conversations) {
      if (c.isDirect && c.peerId == peerId) return c.id;
    }
    final conversation = Conversation(
      id: 'local-conv-${_nextId++}',
      peerId: peerId,
      peerName: _people[peerId] ?? 'Пользователь',
      encrypted: false,
    );
    _conversations.insert(0, conversation);
    return conversation.id;
  }

  @override
  Future<String> createGroup({
    required String title,
    required List<String> memberIds,
  }) async {
    final id = 'local-group-${_nextId++}';
    _members[id] = [
      ChatMember(id: currentUserId(), name: 'Вы', isOwner: true),
      for (final memberId in memberIds)
        ChatMember(id: memberId, name: _people[memberId] ?? 'Участник'),
    ];
    _conversations.insert(
      0,
      Conversation(
        id: id,
        kind: ConversationKind.group,
        title: title.trim(),
        memberCount: _members[id]!.length,
        isOwner: true,
        encrypted: false,
      ),
    );
    return id;
  }

  @override
  Future<List<ChatMember>> loadMembers(String conversationId) async =>
      List.of(_members[conversationId] ?? const []);

  @override
  Future<void> addMembers(String conversationId, List<String> memberIds) async {
    final members = _members.putIfAbsent(conversationId, () => []);
    for (final id in memberIds) {
      if (members.every((m) => m.id != id)) {
        members.add(ChatMember(id: id, name: _people[id] ?? 'Участник'));
      }
    }
  }

  @override
  Future<void> removeMember(String conversationId, String memberId) async {
    _members[conversationId]?.removeWhere((m) => m.id == memberId);
    if (memberId == currentUserId()) {
      _conversations.removeWhere((c) => c.id == conversationId);
    }
  }

  @override
  Future<void> renameGroup(String conversationId, String title) async {
    final index = _conversations.indexWhere((c) => c.id == conversationId);
    if (index == -1) return;
    final old = _conversations[index];
    _conversations[index] = Conversation(
      id: old.id,
      kind: old.kind,
      title: title.trim(),
      memberCount: old.memberCount,
      isOwner: old.isOwner,
      lastMessage: old.lastMessage,
      encrypted: false,
    );
  }

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
