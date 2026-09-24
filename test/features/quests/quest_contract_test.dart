import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/core/links/deep_links.dart';
import 'package:social_world/features/discover/domain/activity.dart';
import 'package:social_world/features/needs/data/supabase_needs_repository.dart';
import 'package:social_world/features/needs/domain/entities/need_request.dart';
import 'package:social_world/features/quests/data/supabase_quests_repository.dart';
import 'package:social_world/features/quests/domain/entities/quest.dart';
import 'package:social_world/features/quests/presentation/widgets/quest_format.dart';

// Договор клиента с функциями миграции 0023: имена колонок, QR-ссылка,
// веса квестов и просьб в слое активности.
void main() {
  group('строка quests_list', () {
    test('разбирается целиком', () {
      final quest = questFromRow({
        'id': 'q1',
        'author_id': 'a1',
        'author_name': 'Кофе у Серёги',
        'avatar_url': null,
        'title': '10 бесплатных кофе',
        'description': 'Скажите, что вы из ChaWo',
        'extra_info': null,
        'photo_url': 'https://x/p.jpg',
        'place_id': null,
        'place_title': 'ул. Навагинская, 12',
        'latitude': 43.583,
        'longitude': 39.721,
        'starts_at': '2026-09-25T09:00:00+00:00',
        'ends_at': null,
        'max_participants': 10,
        'participant_count': 3,
        'status': 'active',
        'finished_at': null,
        'my_status': 'approved',
        'moment_count': 2,
        'is_trail': false,
        'created_at': '2026-09-25T08:00:00+00:00',
      });
      expect(quest.occupancy, '3/10');
      expect(quest.myStatus, QuestParticipationStatus.approved);
      expect(quest.hasLocation, isTrue);
      expect(quest.needsApproval, isTrue);
      expect(quest.acceptsRequests, isTrue);
      expect(quest.momentCount, 2);
      expect(formatOccupancy(quest), 'Участники: 3/10');
    });

    test('без моего участия и без лимита', () {
      final quest = questFromRow({
        'id': 'q2',
        'author_id': 'a1',
        'title': 'Прогулка',
        'starts_at': '2026-09-25T09:00:00Z',
        'participant_count': 4,
        'status': 'finished',
        'finished_at': '2026-09-25T12:00:00Z',
        'is_trail': true,
        'created_at': '2026-09-25T08:00:00Z',
      });
      expect(quest.myStatus, isNull);
      expect(quest.occupancy, '4');
      expect(quest.needsApproval, isFalse);
      expect(quest.isActive, isFalse);
      expect(quest.acceptsRequests, isFalse);
    });
  });

  test('строка city_needs разбирается', () {
    final need = needFromRow({
      'id': 'n1',
      'author_id': 'a1',
      'author_name': 'Ника',
      'body': 'Повесить телевизор',
      'latitude': 43.58,
      'longitude': 39.72,
      'status': 'open',
      'expires_at': '2099-01-01T00:00:00Z',
      'created_at': '2026-09-25T08:00:00Z',
      'response_count': 2,
      'responded_by_me': true,
    });
    expect(need.replyCount, 2);
    expect(need.respondedByMe, isTrue);
    expect(need.isVisible, isTrue);
  });

  group('QR прибытия', () {
    test('ссылка из QR ведёт на квест с кодом', () {
      final uri = DeepLinks.arrivalUri('3f2a9c1e-quest', 'ABCD2345');
      expect(uri.toString(), 'socialworld://quest/3f2a9c1e-quest?arrive=ABCD2345');

      final link = DeepLinks.parse(uri)!;
      expect(link.target, LinkTarget.quest);
      expect(link.arrivalCode, 'ABCD2345');
      expect(link.location, '/quest/3f2a9c1e-quest?arrive=ABCD2345');
    });

    test('обычная ссылка на квест — без отметки прибытия', () {
      final link = DeepLinks.parse(Uri.parse('socialworld://quest/3f2a9c1e-quest'))!;
      expect(link.arrivalCode, isNull);
      expect(link.location, '/quest/3f2a9c1e-quest');
    });

    test('код прибытия у других объектов игнорируется', () {
      final link = DeepLinks.parse(
        Uri.parse('socialworld://event/3f2a9c1e-event?arrive=ABCD2345'),
      )!;
      expect(link.arrivalCode, isNull);
    });

    test('мусор вместо кода не проходит', () {
      final link = DeepLinks.parse(
        Uri.parse('socialworld://quest/3f2a9c1e-quest?arrive=%3Cscript%3E'),
      )!;
      expect(link.arrivalCode, isNull);
    });

    test('просьба открывается по ссылке', () {
      final link = DeepLinks.parse(Uri.parse('socialworld://need/5b1c-need-id'))!;
      expect(link.location, '/need/5b1c-need-id');
    });
  });

  group('квесты и просьбы в слое активности', () {
    final now = DateTime(2026, 9, 25, 18);
    const config = ActivityConfig.defaults;

    test('идущий квест весит как событие и растёт с участниками', () {
      final lonely = ActivityCalculator.weightOf(
        ActivityObject(
          kind: ActivityKind.quest,
          latitude: 0,
          longitude: 0,
          startsAt: now.subtract(const Duration(hours: 1)),
        ),
        now,
        config,
      );
      final crowded = ActivityCalculator.weightOf(
        ActivityObject(
          kind: ActivityKind.quest,
          latitude: 0,
          longitude: 0,
          participants: 10,
          startsAt: now.subtract(const Duration(hours: 1)),
        ),
        now,
        config,
      );
      expect(lonely, config.wQuest);
      expect(crowded, greaterThan(lonely));
    });

    test('долгоживущий квест без окончания весит полностью через сутки', () {
      final weight = ActivityCalculator.weightOf(
        ActivityObject(
          kind: ActivityKind.quest,
          latitude: 0,
          longitude: 0,
          startsAt: now.subtract(const Duration(days: 2)),
        ),
        now,
        config,
      );
      expect(weight, config.wQuest);
    });

    test('закончившийся квест не весит', () {
      final weight = ActivityCalculator.weightOf(
        ActivityObject(
          kind: ActivityKind.quest,
          latitude: 0,
          longitude: 0,
          startsAt: now.subtract(const Duration(hours: 3)),
          endsAt: now.subtract(const Duration(minutes: 1)),
        ),
        now,
        config,
      );
      expect(weight, 0);
    });

    test('открытая просьба весит, истёкшая — нет', () {
      double weigh(DateTime? expires) => ActivityCalculator.weightOf(
        ActivityObject(
          kind: ActivityKind.need,
          latitude: 0,
          longitude: 0,
          createdAt: now.subtract(const Duration(hours: 1)),
          endsAt: expires,
        ),
        now,
        config,
      );
      expect(weigh(now.add(const Duration(days: 1))), config.wNeed);
      expect(weigh(now.subtract(const Duration(minutes: 1))), 0);
    });

    test('просьбы не входят в слой при выбранной категории мест', () {
      final objects = [
        ActivityObject(
          kind: ActivityKind.need,
          latitude: 43.58,
          longitude: 39.72,
          createdAt: now.subtract(const Duration(hours: 1)),
        ),
        const ActivityObject(
          kind: ActivityKind.place,
          latitude: 43.58,
          longitude: 39.72,
          category: 'Еда',
        ),
      ];
      final cells = ActivityCalculator.compute(
        objects,
        ActivityQuery(latitude: 43.58, longitude: 39.72, at: now, categories: {'Еда'}),
        config: const ActivityConfig(minScore: 0),
      );
      expect(cells.single.needCount, 0);
      expect(cells.single.placeCount, 1);
    });

    test('квесты и просьбы считаются в ячейке отдельно', () {
      final cells = ActivityCalculator.compute(
        [
          ActivityObject(
            kind: ActivityKind.quest,
            latitude: 43.58,
            longitude: 39.72,
            startsAt: now,
          ),
          ActivityObject(
            kind: ActivityKind.need,
            latitude: 43.58,
            longitude: 39.72,
            createdAt: now.subtract(const Duration(hours: 1)),
          ),
        ],
        ActivityQuery(latitude: 43.58, longitude: 39.72, at: now),
      );
      expect(cells.single.questCount, 1);
      expect(cells.single.needCount, 1);
      expect(cells.single.eventCount, 0);
    });
  });

  test('маршрут до точки встречи — Яндекс Карты', () {
    final uri = questRouteUri(43.58, 39.72);
    expect(uri.host, 'yandex.ru');
    expect(uri.queryParameters['rtext'], '~43.58,39.72');
  });

  test('статус просьбы по сроку', () {
    final need = NeedRequest(
      id: 'n',
      authorId: 'a',
      authorName: 'А',
      text: 'Ищу напарника',
      createdAt: DateTime(2026),
      expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
    );
    expect(need.isExpired, isTrue);
    expect(need.isVisible, isFalse);
  });
}
