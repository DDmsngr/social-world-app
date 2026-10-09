import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/core/links/deep_links.dart';
import 'package:social_world/features/notifications/notifications.dart';
import 'package:social_world/features/referrals/invites.dart';

void main() {
  group('ссылка-приглашение', () {
    test('веб-ссылка и ссылка приложения дают один код', () {
      expect(InviteLinks.parse(Uri.parse('https://api-socialworld.deepdrift.tech/r/abc234')), 'ABC234');
      expect(InviteLinks.parse(Uri.parse('socialworld://r/ABC234')), 'ABC234');
      expect(InviteLinks.shareUri('ABC234').toString(), 'https://api-socialworld.deepdrift.tech/r/ABC234');
    });

    test('чужие и битые ссылки не принимаются', () {
      expect(InviteLinks.parse(Uri.parse('https://evil.example/r/ABC234')), isNull);
      expect(InviteLinks.parse(Uri.parse('https://api-socialworld.deepdrift.tech/updates/chawo.apk')), isNull);
      expect(InviteLinks.parse(Uri.parse('https://api-socialworld.deepdrift.tech/r/AB')), isNull);
      expect(InviteLinks.parse(Uri.parse('socialworld://post/ABC234')), isNull);
      // Код места (0025) — другая ссылка, её разбирает DeepLinks.
      expect(InviteLinks.parse(Uri.parse('socialworld://ref/ABC234')), isNull);
    });

    test('код из буфера обмена — только в нашем формате', () {
      expect(InviteLinks.fromClipboard('Код приглашения в ChaWo: xyz789'), 'XYZ789');
      expect(InviteLinks.fromClipboard('какой-то текст ABC234'), isNull);
      expect(InviteLinks.fromClipboard(null), isNull);
    });
  });

  test('уведомления о баллах ведут на экран приглашений', () {
    final reward = AppNotification(
      id: 'n',
      kind: NotificationKind.referralReward,
      target: LinkTarget.points,
      targetId: 't',
      createdAt: DateTime(2026),
      actorName: 'Аня',
      title: '100:1',
    );
    expect(reward.text, 'Аня зарегистрировался по вашему приглашению: +100 баллов');
    final deep = AppNotification(
      id: 'n',
      kind: NotificationKind.referralReward,
      target: LinkTarget.points,
      targetId: 't',
      createdAt: DateTime(2026),
      title: '50:2',
    );
    expect(deep.text, contains('Ваш реферал пригласил'));
    expect(reward.location, '/profile/points');
  });

  test('история: подписи статусов и заголовки', () {
    final tx = PointTx.fromJson({
      'id': '1',
      'amount': -100,
      'code': 'referral_activation_expired',
      'status': 'cancelled',
      'at': '2026-10-07T10:00:00Z',
      'reason': 'Реферал не выполнил условия активации. Начисление отменено',
    });
    expect(tx.statusLabel, 'отменено');
    expect(tx.title, startsWith('Реферал не выполнил'));
    final plus = PointTx.fromJson({
      'id': '2',
      'amount': 100,
      'code': 'referral_level_1',
      'status': 'pending',
      'level': 1,
      'who': 'Аня',
      'at': '2026-10-07T10:00:00Z',
    });
    expect(plus.title, 'Приглашение: Аня');
  });
}
