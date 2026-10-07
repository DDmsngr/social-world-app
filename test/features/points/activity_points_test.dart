import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/features/points/activity_points_screen.dart';

void main() {
  test('лайки за день склеиваются в одну строку, отменённые сокращают сумму', () {
    final lines = groupPoints([
      (at: DateTime(2026, 10, 7, 10), reason: 'like', delta: 1, status: null),
      (at: DateTime(2026, 10, 7, 11), reason: 'like', delta: 1, status: null),
      (at: DateTime(2026, 10, 7, 12), reason: 'like', delta: -1, status: null),
      (at: DateTime(2026, 10, 7, 13), reason: 'referral_level_1', delta: 100, status: 'pending'),
      (at: DateTime(2026, 10, 6, 9), reason: 'event_join', delta: 1, status: null),
    ]);
    expect(lines, hasLength(3));
    final like = lines.firstWhere((l) => l.reason == 'like');
    expect(like.amount, 1);
    expect(like.count, 3);
    expect(lines.first.day, DateTime(2026, 10, 7));
    expect(lines.last.reason, 'event_join');
    expect(lines.firstWhere((l) => l.status == 'pending').amount, 100);
  });

  test('отметка и её отмена в один день не оставляют пустой строки', () {
    final lines = groupPoints([
      (at: DateTime(2026, 10, 7, 10), reason: 'like', delta: 1, status: null),
      (at: DateTime(2026, 10, 7, 11), reason: 'like', delta: -1, status: null),
    ]);
    expect(lines, isEmpty);
  });

  test('понятные подписи причин', () {
    expect(pointsReasonLabel('referral_level_1'), 'Приглашённый друг');
    expect(pointsReasonLabel('referral_level_3'), contains('уровень 3'));
    expect(pointsReasonLabel('like'), contains('публикациях'));
    expect(pointsReasonLabel('что-то новое'), 'Прочее');
  });
}
