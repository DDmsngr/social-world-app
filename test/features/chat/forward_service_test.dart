import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/features/chat/data/local_chat_repository.dart';
import 'package:social_world/features/chat/domain/entities/chat_message.dart';
import 'package:social_world/features/chat/domain/entities/chat_meta.dart';
import 'package:social_world/features/chat/domain/entities/conversation.dart';
import 'package:social_world/features/chat/domain/forward_service.dart';

class _Sent {
  _Sent(this.conversationId, this.kind, this.text, this.options, {this.file});
  final String conversationId;
  final MessageKind kind;
  final String? text;
  final SendOptions options;
  final String? file;
}

/// Запоминает, что и куда ушло, и может «сломать» один из чатов.
class _Spy extends LocalChatRepository {
  _Spy({this.failFor}) : super(currentUserId: () => 'me');

  final String? failFor;
  final sent = <_Sent>[];
  var downloads = 0;

  @override
  Future<ChatMessage> send({
    required String conversationId,
    required String text,
    MessageKind kind = MessageKind.text,
    SendOptions options = SendOptions.none,
  }) {
    if (conversationId == failFor) throw StateError('нет ключей');
    sent.add(_Sent(conversationId, kind, text, options));
    return super.send(
      conversationId: conversationId,
      text: text,
      kind: kind,
      options: options,
    );
  }

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
  }) {
    if (conversationId == failFor) throw StateError('нет ключей');
    sent.add(_Sent(conversationId, kind, caption, options, file: filePath));
    return super.sendAttachment(
      conversationId: conversationId,
      kind: kind,
      filePath: filePath,
      name: name,
      mime: mime,
      durationMs: durationMs,
      waveform: waveform,
      caption: caption,
      options: options,
    );
  }

  @override
  Future<String> attachmentFile(ChatMessage message) {
    downloads++;
    return super.attachmentFile(message);
  }
}

void main() {
  const alina = Conversation(id: 'c-a', peerId: 'p1', peerName: 'Алина', encrypted: false);
  const mark = Conversation(id: 'c-m', peerId: 'p2', peerName: 'Марк', encrypted: false);

  ChatMessage text(String body, {String? forwardedFrom}) => ChatMessage(
    id: 't1',
    conversationId: 'src',
    senderId: 'p1',
    sentAt: DateTime(2026, 10, 1),
    text: body,
    forwardedFrom: forwardedFrom,
  );

  final photo = ChatMessage(
    id: 'ph1',
    conversationId: 'src',
    senderId: 'p1',
    sentAt: DateTime(2026, 10, 1),
    kind: MessageKind.image,
    text: 'Закат',
    attachment: const ChatAttachment(path: 'src/ph1', size: 10, name: 'a.jpg', mime: 'image/jpeg'),
  );

  group('forwardMessages', () {
    test('текст уходит в каждый чат с пометкой автора оригинала', () async {
      final repo = _Spy();
      addTearDown(repo.dispose);
      final result = await forwardMessages(
        repository: repo,
        messages: [text('Встречаемся в семь')],
        targets: [alina, mark],
        authorOf: (_) => 'Саша',
      );
      expect(result.allDelivered, isTrue);
      expect(result.delivered, {'c-a', 'c-m'});
      expect(repo.sent.map((s) => s.conversationId), ['c-a', 'c-m']);
      expect(repo.sent.every((s) => s.options.forwardedFrom == 'Саша'), isTrue);
      expect(repo.sent.first.text, 'Встречаемся в семь');
    });

    test('вложение скачивается один раз и уходит с подписью везде', () async {
      final repo = _Spy();
      addTearDown(repo.dispose);
      final result = await forwardMessages(
        repository: repo,
        messages: [photo],
        targets: [alina, mark],
        authorOf: (_) => 'Саша',
      );
      expect(result.delivered, {'c-a', 'c-m'});
      expect(repo.downloads, 1, reason: 'файл качается один раз, а не на каждый чат');
      expect(repo.sent.map((s) => s.kind), [MessageKind.image, MessageKind.image]);
      expect(repo.sent.map((s) => s.text), ['Закат', 'Закат']);
    });

    test('сбой в одном чате не мешает остальным и попадает в итог', () async {
      final repo = _Spy(failFor: 'c-a');
      addTearDown(repo.dispose);
      final result = await forwardMessages(
        repository: repo,
        messages: [text('Привет')],
        targets: [alina, mark],
        authorOf: (_) => 'Саша',
      );
      expect(result.delivered, {'c-m'});
      expect(result.failed.keys, ['c-a']);
      expect(result.allDelivered, isFalse);
    });

    test('несколько сообщений уходят по порядку', () async {
      final repo = _Spy();
      addTearDown(repo.dispose);
      await forwardMessages(
        repository: repo,
        messages: [text('раз'), text('два')],
        targets: [alina],
        authorOf: (_) => 'Саша',
      );
      expect(repo.sent.map((s) => s.text), ['раз', 'два']);
    });
  });

  group('forwardAuthor', () {
    test('своё сообщение — моё имя', () {
      final mine = ChatMessage(
        id: 'm',
        conversationId: 'c',
        senderId: 'me',
        sentAt: DateTime(2026, 10, 1),
        text: 'x',
      );
      expect(forwardAuthor(mine, myId: 'me', myName: 'Алексей'), 'Алексей');
    });

    test('в группе — имя отправителя, в личном — имя собеседника', () {
      final groupMsg = ChatMessage(
        id: 'm',
        conversationId: 'c',
        senderId: 'p9',
        sentAt: DateTime(2026, 10, 1),
        senderName: 'Лена',
        text: 'x',
      );
      expect(forwardAuthor(groupMsg, myId: 'me', myName: 'Я'), 'Лена');
      expect(
        forwardAuthor(text('x'), myId: 'me', myName: 'Я', source: alina),
        'Алина',
      );
    });

    test('пересланное пересылкой сохраняет первого автора', () {
      expect(
        forwardAuthor(
          text('x', forwardedFrom: 'Первый автор'),
          myId: 'me',
          myName: 'Я',
          source: alina,
        ),
        'Первый автор',
      );
    });

    test('если имени нет совсем — нейтральная подпись', () {
      expect(forwardAuthor(text('x'), myId: 'me', myName: 'Я'), 'Пользователь');
    });
  });
}
