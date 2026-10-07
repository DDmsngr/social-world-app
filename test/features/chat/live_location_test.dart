import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/features/chat/live_location/live_location.dart';

LiveShare _share({DateTime? expires}) => LiveShare(
  id: 's',
  conversationId: 'c',
  userId: 'u',
  startedAt: DateTime(2026, 10, 7, 19),
  expiresAt: expires,
);

void main() {
  final now = DateTime(2026, 10, 7, 19, 0);

  test('сколько осталось', () {
    expect(liveRemainingLabel(_share(), now), 'пока не выключит');
    expect(liveRemainingLabel(_share(expires: DateTime(2026, 10, 7, 19, 12)), now), 'ещё 12 мин');
    expect(liveRemainingLabel(_share(expires: DateTime(2026, 10, 7, 20, 30)), now), 'до 20:30');
  });

  test('свежесть точки', () {
    expect(liveUpdatedLabel(null, now), 'ждём первую точку');
    expect(liveUpdatedLabel(now.subtract(const Duration(seconds: 10)), now), 'обновлено только что');
    expect(liveUpdatedLabel(now.subtract(const Duration(minutes: 3)), now), 'обновлено 3 мин назад');
  });

  test('точка кодируется и читается обратно, мусор — null', () {
    const p = LivePoint(lat: 44.6, lng: 33.52, accuracy: 7);
    final back = LivePoint.decode(p.encode())!;
    expect(back.lat, 44.6);
    expect(back.lng, 33.52);
    expect(back.accuracy, 7);
    expect(LivePoint.decode('не json'), isNull);
    expect(LivePoint.decode(null), isNull);
  });

  test('отправляем при сдвиге или раз в 30 секунд', () {
    expect(LiveLocationSharer.shouldSend(lastSentAt: null, movedMeters: null, now: now), isTrue);
    final recent = now.subtract(const Duration(seconds: 5));
    expect(LiveLocationSharer.shouldSend(lastSentAt: recent, movedMeters: 5, now: now), isFalse);
    expect(LiveLocationSharer.shouldSend(lastSentAt: recent, movedMeters: 25, now: now), isTrue);
    final old = now.subtract(const Duration(seconds: 31));
    expect(LiveLocationSharer.shouldSend(lastSentAt: old, movedMeters: 0, now: now), isTrue);
  });
}
