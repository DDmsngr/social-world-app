import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/features/chat/data/message_envelope.dart';
import 'package:social_world/features/chat/domain/entities/chat_message.dart';
import 'package:social_world/features/chat/domain/entities/chat_meta.dart';

// Конверт зашифрованного сообщения личного диалога. Главное, что здесь
// защищаем: обычный текст едет голой строкой (его читают и старые версии),
// а ответ и пересылка не ломают ни вложения, ни текст, похожий на JSON.
void main() {
  const reply = ChatReply(
    messageId: 'm-1',
    senderName: 'Алина',
    preview: 'Завтра в семь?',
  );

  group('текст', () {
    test('без ответа и пересылки — голая строка, как в первых версиях', () {
      expect(
        MessageEnvelope.encode(kind: MessageKind.text, text: 'Привет'),
        'Привет',
      );
      final decoded = MessageEnvelope.decode(
        'Привет',
        rowKind: MessageKind.text,
      );
      expect(decoded.text, 'Привет');
      expect(decoded.meta.isEmpty, isTrue);
    });

    test('с ответом и пересылкой — конверт, который читается обратно', () {
      final encoded = MessageEnvelope.encode(
        kind: MessageKind.text,
        text: 'Да, приду',
        meta: const ChatMeta(reply: reply, forwardedFrom: 'Марк'),
      );
      expect(encoded, startsWith('{"cw":1,'));

      final decoded = MessageEnvelope.decode(encoded, rowKind: MessageKind.text);
      expect(decoded.kind, MessageKind.text);
      expect(decoded.text, 'Да, приду');
      expect(decoded.meta.reply?.messageId, 'm-1');
      expect(decoded.meta.reply?.senderName, 'Алина');
      expect(decoded.meta.reply?.preview, 'Завтра в семь?');
      expect(decoded.meta.forwardedFrom, 'Марк');
    });

    test('текст, который человек набрал похожим на JSON, остаётся текстом', () {
      for (final typed in [
        '{"v":1,"kind":"image","text":"x"}',
        '{"cw":2,"text":"подмена"}',
        '{"cw":1',
        '{"cw":1,"text":',
        '{"a":1}',
      ]) {
        final decoded = MessageEnvelope.decode(typed, rowKind: MessageKind.text);
        expect(decoded.text, typed, reason: typed);
        expect(decoded.kind, MessageKind.text, reason: typed);
        expect(decoded.meta.isEmpty, isTrue, reason: typed);
      }
    });

    test('в конверте текста тип берётся «текст», что бы там ни было написано', () {
      const forged = '{"cw":1,"kind":"image","text":"привет"}';
      final decoded = MessageEnvelope.decode(forged, rowKind: MessageKind.text);
      expect(decoded.kind, MessageKind.text);
      expect(decoded.attachment, isNull);
    });
  });

  group('вложения', () {
    const attachment = ChatAttachment(
      path: 'c/f',
      size: 1234,
      name: 'a.jpg',
      mime: 'image/jpeg',
      key: 'секрет',
    );

    test('вложение с подписью и ответом сохраняет всё', () {
      final encoded = MessageEnvelope.encode(
        kind: MessageKind.image,
        text: 'Смотри',
        attachment: attachment,
        meta: const ChatMeta(reply: reply),
      );
      final decoded = MessageEnvelope.decode(
        encoded,
        rowKind: MessageKind.image,
      );
      expect(decoded.kind, MessageKind.image);
      expect(decoded.text, 'Смотри');
      expect(decoded.attachment?.path, 'c/f');
      expect(decoded.attachment?.key, 'секрет');
      expect(decoded.meta.reply?.preview, 'Завтра в семь?');
    });

    test('старый конверт без meta читается как раньше', () {
      const legacy =
          '{"v":1,"kind":"voice","a":{"path":"c/v","size":10,"duration_ms":3000}}';
      final decoded = MessageEnvelope.decode(legacy, rowKind: MessageKind.voice);
      expect(decoded.kind, MessageKind.voice);
      expect(decoded.attachment?.durationMs, 3000);
      expect(decoded.meta.isEmpty, isTrue);
    });

    test('битый конверт вложения не роняет экран', () {
      final decoded = MessageEnvelope.decode(
        'это не json',
        rowKind: MessageKind.image,
      );
      expect(decoded.kind, MessageKind.text);
      expect(decoded.text, 'это не json');
    });

    test('без ответа и пересылки в конверте нет ключа meta', () {
      final encoded = MessageEnvelope.encode(
        kind: MessageKind.file,
        attachment: attachment,
      );
      expect(encoded, isNot(contains('"m"')));
    });
  });

  group('ChatReply', () {
    test('цитата обрезается и берёт подпись типа, если текста нет', () {
      final long = ChatMessage(
        id: 'm',
        conversationId: 'c',
        senderId: 's',
        sentAt: DateTime(2026, 9, 30),
        text: 'я' * 300,
      );
      final cut = ChatReply.of(long, senderName: 'Саша');
      expect(cut.preview.length, ChatReply.previewLength + 1);
      expect(cut.preview, endsWith('…'));

      final photo = ChatMessage(
        id: 'p',
        conversationId: 'c',
        senderId: 's',
        sentAt: DateTime(2026, 9, 30),
        kind: MessageKind.image,
      );
      expect(ChatReply.of(photo, senderName: 'Саша').preview, '📷 Фото');
    });

    test('цитата без id не разбирается', () {
      expect(ChatReply.fromJson({'n': 'x'}), isNull);
      expect(ChatReply.fromJson('строка'), isNull);
    });
  });
}
