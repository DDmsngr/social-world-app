import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/features/chat/domain/day_label.dart';
import 'package:social_world/features/chat/presentation/providers/chat_typing_providers.dart';

void main() {
  final now = DateTime(2026, 10, 7, 16, 30);

  test('сегодня, вчера, дата, дата прошлого года', () {
    expect(chatDayLabel(DateTime(2026, 10, 7, 0, 5), now), 'Сегодня');
    expect(chatDayLabel(DateTime(2026, 10, 6, 23, 59), now), 'Вчера');
    expect(chatDayLabel(DateTime(2026, 10, 1, 12), now), '1 октября');
    expect(chatDayLabel(DateTime(2025, 12, 31, 12), now), '31 декабря 2025');
  });

  test('один день — по календарю, а не по 24 часам', () {
    expect(sameDay(DateTime(2026, 10, 7, 0, 1), DateTime(2026, 10, 7, 23, 59)), isTrue);
    expect(sameDay(DateTime(2026, 10, 6, 23, 59), DateTime(2026, 10, 7, 0, 1)), isFalse);
  });

  test('при отправке вложения вместо «печатает» — что именно отправляет', () {
    final entry = TypingEntry(profileId: 'u', name: 'Аня', phrase: 3, until: DateTime(2030), activity: 'video_note');
    expect(entry.phraseText, 'отправляет видеосообщение…');
    final typing = TypingEntry(profileId: 'u', name: 'Аня', phrase: 0, until: DateTime(2030));
    expect(typing.phraseText, typingPhrases.first);
  });
}
