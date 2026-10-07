import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/features/chat/domain/entities/chat_message.dart';
import 'package:social_world/features/chat/domain/entities/conversation.dart';
import 'package:social_world/features/chat/presentation/chat_looks.dart';
import 'package:social_world/features/chat/presentation/providers/chat_settings_providers.dart';
import 'package:social_world/features/chat/presentation/providers/chat_typing_providers.dart';

Conversation chat({DateTime? lastAt}) => Conversation(
  id: 'c1',
  lastMessage: lastAt == null
      ? null
      : ChatMessage(
          id: 'm1',
          conversationId: 'c1',
          senderId: 'u2',
          sentAt: lastAt,
          kind: MessageKind.text,
          text: 'привет',
        ),
);

TypingEntry typing(String id, String name, int phrase) => TypingEntry(
  profileId: id,
  name: name,
  phrase: phrase,
  until: DateTime(2030),
);

void main() {
  final mark = DateTime(2026, 10, 7, 12);

  group('архив и «удалён у меня»', () {
    test('без настроек чат виден', () {
      expect(hiddenFromList(chat(lastAt: mark), ChatSettings.none), isFalse);
    });

    test('архивный чат скрыт, пока в нём тихо, и возвращается с новым сообщением', () {
      final archived = ChatSettings(archivedAt: mark);
      expect(hiddenFromList(chat(lastAt: mark.subtract(const Duration(hours: 1))), archived), isTrue);
      expect(hiddenFromList(chat(lastAt: mark.add(const Duration(minutes: 1))), archived), isFalse);
    });

    test('удалённый у себя ведёт себя так же', () {
      final cleared = ChatSettings(clearedAt: mark);
      expect(hiddenFromList(chat(lastAt: mark.subtract(const Duration(days: 2))), cleared), isTrue);
      expect(hiddenFromList(chat(lastAt: mark.add(const Duration(seconds: 5))), cleared), isFalse);
    });

    test('в «Архив» попадает только архивный, не удалённый', () {
      final old = mark.subtract(const Duration(hours: 1));
      expect(inArchive(chat(lastAt: old), ChatSettings(archivedAt: mark)), isTrue);
      expect(inArchive(chat(lastAt: old), ChatSettings(archivedAt: mark, clearedAt: mark)), isFalse);
      expect(inArchive(chat(lastAt: old), ChatSettings.none), isFalse);
    });
  });

  group('«печатает»', () {
    test('в личном чате — одна фраза без имени', () {
      expect(typingLabel([typing('u2', 'Аня', 1)], direct: true), typingPhrases[1]);
    });

    test('в группе — с именем, двое и больше — коротко', () {
      expect(typingLabel([typing('u2', 'Аня', 2)], direct: false), 'Аня ${typingPhrases[2]}');
      expect(typingLabel([typing('u2', 'Аня', 0), typing('u3', 'Боря', 0)], direct: false), 'Аня и Боря печатают…');
      expect(
        typingLabel([typing('u2', 'Аня', 0), typing('u3', 'Боря', 0), typing('u4', 'Вика', 0)], direct: false),
        'Аня и ещё 2 печатают…',
      );
    });

    test('никто не пишет — пусто; номер фразы не выходит за список', () {
      expect(typingLabel(const [], direct: true), '');
      expect(typing('u', 'х', 999).phraseText, isNotEmpty);
    });

    test('фраз не меньше десяти и среди них есть обычное «печатает…»', () {
      expect(typingPhrases.length, greaterThanOrEqualTo(10));
      expect(typingPhrases, contains('печатает…'));
      expect(typingPhrases.toSet().length, typingPhrases.length);
    });
  });

  group('звуки и фоны совпадают с базой', () {
    test('звуки — те, что разрешает check в 0057 и функция push-send', () {
      expect([for (final s in chatSounds) s.id], ['ding', 'pop', 'chime', 'drop', 'knock']);
    });

    test('идентификаторы фонов короче лимита колонки (40) и уникальны', () {
      final ids = [for (final w in chatWallpapers) w.id];
      expect(ids.toSet().length, ids.length);
      expect(ids.every((id) => id.length <= 40), isTrue);
      expect(chatWallpaperById('sunset')?.label, 'Закат');
      expect(chatWallpaperById('нет такого'), isNull);
      expect(chatWallpaperLabel(null), 'Обычный');
      expect(chatSoundLabel(null), 'Стандартный');
    });
  });
}
