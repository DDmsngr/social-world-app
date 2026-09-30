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
    test('текст: копировать и удалить, без галереи', () {
      expect(messageActions(message()), [
        MessageAction.copy,
        MessageAction.delete,
      ]);
    });

    test('фото без подписи: галерея, поделиться, удалить', () {
      expect(
        messageActions(
          message(kind: MessageKind.image, text: null, withFile: true),
        ),
        [
          MessageAction.saveToGallery,
          MessageAction.share,
          MessageAction.delete,
        ],
      );
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
