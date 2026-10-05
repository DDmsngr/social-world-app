import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/features/chat/domain/entities/chat_message.dart';
import 'package:social_world/features/chat/domain/message_actions.dart';

void main() {
  ChatMessage message({
    String sender = 'me',
    MessageKind kind = MessageKind.text,
    String? text = 'Привет',
    bool withFile = false,
  }) => ChatMessage(
    id: 'm1',
    conversationId: 'c1',
    senderId: sender,
    sentAt: DateTime(2026, 9, 30),
    kind: kind,
    text: text,
    attachment: withFile
        ? const ChatAttachment(path: 'c1/file', size: 10, mime: 'image/jpeg')
        : null,
  );

  group('messageActions', () {
    test('текст: ответить, копировать, переслать, удалить — без галереи', () {
      expect(messageActions(message()), [
        MessageAction.reply,
        MessageAction.copy,
        MessageAction.copyPart,
        MessageAction.forward,
        MessageAction.editForward,
        MessageAction.bookmark,
        MessageAction.info,
        MessageAction.delete,
      ]);
    });

    test('фото без подписи: ответить, галерея, поделиться, переслать, удалить', () {
      expect(
        messageActions(
          message(kind: MessageKind.image, text: null, withFile: true),
        ),
        [
          MessageAction.reply,
          MessageAction.saveToGallery,
          MessageAction.share,
          MessageAction.forward,
          MessageAction.editForward,
          MessageAction.bookmark,
          MessageAction.info,
          MessageAction.delete,
        ],
      );
    });

    test('закреп: только с правом; закреплённое — «открепить»', () {
      expect(messageActions(message()), isNot(contains(MessageAction.pin)));
      expect(messageActions(message(), canPin: true), contains(MessageAction.pin));
      final pinned = messageActions(message(), canPin: true, isPinned: true);
      expect(pinned, contains(MessageAction.unpin));
      expect(pinned, isNot(contains(MessageAction.pin)));
    });

    test('закладка: поставить или убрать по состоянию', () {
      expect(messageActions(message()), contains(MessageAction.bookmark));
      final marked = messageActions(message(), isBookmarked: true);
      expect(marked, contains(MessageAction.unbookmark));
      expect(marked, isNot(contains(MessageAction.bookmark)));
    });

    test('в закрытом чате отвечать нельзя, пересылать можно', () {
      final actions = messageActions(message(), canReply: false);
      expect(actions, isNot(contains(MessageAction.reply)));
      expect(actions, contains(MessageAction.forward));
    });

    test('подпись не сошлась или не расшифровалось — ни ответа, ни пересылки', () {
      for (final bad in [
        ChatMessage(
          id: 'm1',
          conversationId: 'c1',
          senderId: 'peer',
          sentAt: DateTime(2026, 9, 30),
          text: 'подделка',
          signatureValid: false,
        ),
        ChatMessage(
          id: 'm2',
          conversationId: 'c1',
          senderId: 'peer',
          sentAt: DateTime(2026, 9, 30),
          text: 'Не удалось расшифровать сообщение',
          status: MessageStatus.failed,
        ),
      ]) {
        final actions = messageActions(bad);
        expect(actions, isNot(contains(MessageAction.reply)), reason: bad.id);
        expect(actions, isNot(contains(MessageAction.forward)), reason: bad.id);
        // Удалить у себя можно всегда.
        expect(actions, contains(MessageAction.delete), reason: bad.id);
      }
    });

    test('фото с подписью можно ещё и скопировать', () {
      expect(
        messageActions(message(kind: MessageKind.image, withFile: true)),
        contains(MessageAction.copy),
      );
    });

    test('файл и голосовое — не в галерею', () {
      for (final kind in [MessageKind.file, MessageKind.voice]) {
        final actions = messageActions(
          message(kind: kind, text: null, withFile: true),
        );
        expect(actions, isNot(contains(MessageAction.saveToGallery)));
        expect(actions, contains(MessageAction.share));
      }
    });

    test('удалить — всегда последним', () {
      final actions = messageActions(
        message(kind: MessageKind.video, withFile: true),
      );
      expect(actions.last, MessageAction.delete);
    });
  });

  group('canDeleteForEveryone', () {
    test('своё — везде', () {
      expect(
        canDeleteForEveryone(
          message(),
          myId: 'me',
          isDirect: true,
          isGroupOwner: false,
        ),
        isTrue,
      );
    });

    test('чужое в личном — нет, даже если «владелец»', () {
      expect(
        canDeleteForEveryone(
          message(sender: 'peer'),
          myId: 'me',
          isDirect: true,
          isGroupOwner: true,
        ),
        isFalse,
      );
    });

    test('чужое в группе — только владельцу', () {
      final peer = message(sender: 'peer');
      expect(
        canDeleteForEveryone(
          peer,
          myId: 'me',
          isDirect: false,
          isGroupOwner: true,
        ),
        isTrue,
      );
      expect(
        canDeleteForEveryone(
          peer,
          myId: 'me',
          isDirect: false,
          isGroupOwner: false,
        ),
        isFalse,
      );
    });
  });
}
