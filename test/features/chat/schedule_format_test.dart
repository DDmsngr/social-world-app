import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/features/chat/domain/schedule_format.dart';

void main() {
  final now = DateTime(2026, 10, 1, 8, 30);

  group('validateSendAt', () {
    test('раньше чем через минуту — нельзя', () {
      expect(validateSendAt(now.add(const Duration(seconds: 30)), now), isNotNull);
      expect(validateSendAt(now.subtract(const Duration(hours: 1)), now), isNotNull);
    });

    test('через минуту и позже — можно', () {
      expect(validateSendAt(now.add(const Duration(minutes: 1)), now), isNull);
      expect(validateSendAt(now.add(const Duration(days: 30)), now), isNull);
    });

    test('дальше года — нельзя', () {
      expect(validateSendAt(now.add(const Duration(days: 366)), now), isNotNull);
      expect(validateSendAt(now.add(const Duration(days: 365)), now), isNull);
    });
  });

  group('formatScheduledAt', () {
    test('сегодня и завтра — словами', () {
      expect(formatScheduledAt(DateTime(2026, 10, 1, 18, 5), now), 'сегодня в 18:05');
      expect(formatScheduledAt(DateTime(2026, 10, 2, 9, 0), now), 'завтра в 09:00');
    });

    test('дальше — числом и месяцем, год только если он не текущий', () {
      expect(formatScheduledAt(DateTime(2026, 10, 3, 9, 0), now), '3 окт. в 09:00');
      expect(formatScheduledAt(DateTime(2026, 5, 20, 7, 45), now.add(const Duration(days: -200))), '20 мая в 07:45');
      expect(formatScheduledAt(DateTime(2027, 1, 15, 12, 0), now), '15 янв. 2027 в 12:00');
    });

    test('полночь считается завтрашним днём, а не сегодняшним', () {
      expect(formatScheduledAt(DateTime(2026, 10, 2, 0, 0), now), 'завтра в 00:00');
    });
  });
}
