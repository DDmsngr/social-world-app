import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/features/chat/presentation/widgets/emoji_panel.dart';

// Кнопка 🙂 раньше отправляла эмодзи отдельным сообщением-«стикером», и
// набранный текст оставался без смайлика. Теперь эмодзи встаёт в текст на
// место курсора и ничего не отправляет.
void main() {
  TextEditingValue at(String text, int offset) => TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: offset),
  );

  group('insertAtSelection', () {
    test('вставляет в позицию курсора, курсор встаёт после эмодзи', () {
      final result = insertAtSelection(at('Приветмир', 6), '👋');
      expect(result.text, 'Привет👋мир');
      expect(result.selection.baseOffset, 'Привет👋'.length);
    });

    test('заменяет выделенное', () {
      final value = const TextEditingValue(
        text: 'ха ха ха',
        selection: TextSelection(baseOffset: 3, extentOffset: 5),
      );
      expect(insertAtSelection(value, '😂').text, 'ха 😂 ха');
    });

    test('поле без курсора — в конец', () {
      final value = const TextEditingValue(text: 'Ок');
      expect(insertAtSelection(value, '👍').text, 'Ок👍');
    });
  });

  group('deleteBeforeSelection', () {
    test('стирает эмодзи из нескольких кодовых точек целиком', () {
      for (final emoji in ['👍🏽', '🇷🇺', '❤️‍🔥', '👨‍👩‍👧']) {
        final text = 'a$emoji';
        final result = deleteBeforeSelection(at(text, text.length));
        expect(result.text, 'a', reason: emoji);
        expect(result.selection.baseOffset, 1);
      }
    });

    test('в начале строки ничего не делает', () {
      final value = at('abc', 0);
      expect(deleteBeforeSelection(value), value);
    });

    test('стирает выделение', () {
      final value = const TextEditingValue(
        text: 'abcdef',
        selection: TextSelection(baseOffset: 1, extentOffset: 4),
      );
      expect(deleteBeforeSelection(value).text, 'aef');
    });
  });

  group('emojiOnlyCount', () {
    test('1–3 эмодзи без текста — крупно', () {
      expect(emojiOnlyCount('😁'), 1);
      expect(emojiOnlyCount(' 👻 😀 '), 2);
      expect(emojiOnlyCount('🇷🇺👍🏽❤️'), 3);
    });

    test('текст, цифры, больше трёх — обычный пузырь', () {
      expect(emojiOnlyCount('привет 😂'), 0);
      expect(emojiOnlyCount('1'), 0);
      expect(emojiOnlyCount('😀😀😀😀'), 0);
      expect(emojiOnlyCount(''), 0);
      expect(emojiOnlyCount(null), 0);
    });
  });
}
