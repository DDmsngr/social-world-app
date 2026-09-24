import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/core/errors/friendly_error.dart';
import 'package:social_world/core/errors/rule_violation.dart';
import 'package:social_world/features/quests/data/local_quests_repository.dart';
import 'package:social_world/features/quests/domain/entities/quest.dart';

// Заглушка повторяет правила функций миграции 0023. Эти тесты — исполняемая
// спецификация цикла ТЗ «заявка → одобрение → QR → участие → завершение».
void main() {
  late String me;
  late DateTime now;
  late LocalQuestsRepository repo;

  setUp(() {
    me = 'organizer';
    now = DateTime(2026, 9, 25, 12);
    repo = LocalQuestsRepository(
      currentUserId: () => me,
      currentUserName: () => me,
      clock: () => now,
      seed: false,
    );
  });

  Future<String> createQuest({int? limit, DateTime? endsAt}) async {
    final previous = me;
    me = 'organizer';
    await repo.acceptRules(QuestRulesConsent.currentVersion);
    final id = await repo.createQuest(
      title: 'Велопрогулка по порту',
      startsAt: now,
      endsAt: endsAt,
      latitude: 43.58,
      longitude: 39.72,
      placeTitle: 'Морской порт',
      maxParticipants: limit,
    );
    me = previous;
    return id;
  }

  Matcher rule(String code) =>
      throwsA(isA<RuleViolation>().having((e) => e.code, 'code', code));

  group('создание', () {
    test('без принятых правил квест не создаётся (п. 49)', () async {
      expect(
        repo.createQuest(title: 'Прогулка', startsAt: now),
        rule('quest_rules_required'),
      );
    });

    test('принятые правила хранят версию и время (п. 50)', () async {
      expect(await repo.loadRulesConsent(), isNull);
      await repo.acceptRules(QuestRulesConsent.currentVersion);
      final consent = await repo.loadRulesConsent();
      expect(consent!.version, QuestRulesConsent.currentVersion);
      expect(consent.acceptedAt, now);
      expect(consent.isCurrent, isTrue);
    });

    test('старую версию правил принять нельзя', () async {
      expect(repo.acceptRules(0), rule('quest_rules_outdated'));
    });
  });

  group('заявки и лимит', () {
    test('без лимита заявка одобряется сразу', () async {
      final id = await createQuest();
      me = 'lev';
      expect(await repo.requestJoin(id), QuestParticipationStatus.approved);
      expect((await repo.loadQuest(id))!.participantCount, 1);
    });

    test('с лимитом заявку решает организатор, повтор идемпотентен', () async {
      final id = await createQuest(limit: 1);
      me = 'lev';
      expect(await repo.requestJoin(id), QuestParticipationStatus.requested);
      expect(await repo.requestJoin(id), QuestParticipationStatus.requested);
      // Заявка место не занимает — только одобрение.
      expect((await repo.loadQuest(id))!.participantCount, 0);

      me = 'organizer';
      final requests = await repo.loadParticipants(id);
      expect(requests.single.status, QuestParticipationStatus.requested);
      await repo.decideRequest(participationId: requests.single.id, approved: true);
      expect((await repo.loadQuest(id))!.occupancy, '1/1');
    });

    test('полный квест не принимает новых заявок (п. 24)', () async {
      final id = await createQuest(limit: 1);
      me = 'lev';
      await repo.requestJoin(id);
      me = 'alex';
      await repo.requestJoin(id);

      me = 'organizer';
      final list = await repo.loadParticipants(id);
      await repo.decideRequest(participationId: list.first.id, approved: true);
      // Второе одобрение сверх лимита — отказ.
      expect(
        repo.decideRequest(participationId: list.last.id, approved: true),
        rule('quest_full'),
      );

      me = 'viktor';
      expect(repo.requestJoin(id), rule('quest_full'));
      expect((await repo.loadQuest(id))!.acceptsRequests, isFalse);
    });

    test('отклонённый не может подать заявку снова', () async {
      final id = await createQuest(limit: 5);
      me = 'lev';
      await repo.requestJoin(id);
      me = 'organizer';
      final request = (await repo.loadParticipants(id)).single;
      await repo.decideRequest(participationId: request.id, approved: false);
      me = 'lev';
      expect(repo.requestJoin(id), rule('quest_denied'));
    });

    test('чужой квест одобрять нельзя', () async {
      final id = await createQuest(limit: 5);
      me = 'lev';
      await repo.requestJoin(id);
      me = 'organizer';
      final request = (await repo.loadParticipants(id)).single;
      me = 'alex';
      expect(
        repo.decideRequest(participationId: request.id, approved: true),
        rule('quest_not_yours'),
      );
    });

    test('в свой квест заявку не подать', () async {
      final id = await createQuest();
      me = 'organizer';
      expect(repo.requestJoin(id), rule('quest_is_yours'));
    });
  });

  group('несколько квестов одновременно (п. 25)', () {
    test('у человека может быть несколько активных участий', () async {
      final bike = await createQuest();
      final coffee = await createQuest(limit: 10);
      me = 'lev';
      await repo.requestJoin(bike);
      await repo.requestJoin(coffee);
      final active = await repo.myQuests(activeOnly: true);
      expect(active.map((q) => q.id), containsAll([bike, coffee]));
    });

    test('завершение одного не трогает другое (п. 34)', () async {
      final bike = await createQuest();
      final coffee = await createQuest();
      me = 'lev';
      await repo.requestJoin(bike);
      await repo.requestJoin(coffee);
      await repo.completeParticipation(coffee);

      expect((await repo.loadQuest(coffee))!.myStatus, QuestParticipationStatus.completed);
      expect((await repo.loadQuest(bike))!.myStatus, QuestParticipationStatus.approved);
      // Сам квест продолжает идти.
      expect((await repo.loadQuest(coffee))!.isActive, isTrue);
      // Повтор «Завершить» — не ошибка.
      await repo.completeParticipation(coffee);
    });
  });

  group('QR прибытия (п. 32, 33)', () {
    test('одобренный участник отмечается кодом', () async {
      final id = await createQuest(limit: 3);
      me = 'lev';
      await repo.requestJoin(id);
      me = 'organizer';
      final request = (await repo.loadParticipants(id)).single;
      await repo.decideRequest(participationId: request.id, approved: true);
      final code = await repo.arrivalCode(id);

      me = 'lev';
      // Регистр и пробелы не важны — человек мог ввести код руками.
      final spaced = '${code.substring(0, 4).toLowerCase()} ${code.substring(4)}';
      expect(
        await repo.confirmArrival(questId: id, code: spaced),
        QuestParticipationStatus.arrived,
      );
      expect((await repo.loadQuest(id))!.participantCount, 1);
    });

    test('неверный код не принимается', () async {
      final id = await createQuest();
      me = 'lev';
      expect(repo.confirmArrival(questId: id, code: 'AAAA2222'), rule('quest_bad_code'));
    });

    test('без лимита можно отметиться сразу, без заявки', () async {
      final id = await createQuest();
      me = 'organizer';
      final code = await repo.arrivalCode(id);
      me = 'lev';
      expect(await repo.confirmArrival(questId: id, code: code), QuestParticipationStatus.arrived);
    });

    test('с лимитом без одобрения отметиться нельзя', () async {
      final id = await createQuest(limit: 3);
      me = 'organizer';
      final code = await repo.arrivalCode(id);
      me = 'lev';
      expect(repo.confirmArrival(questId: id, code: code), rule('quest_not_approved'));
    });

    test('после смены кода старый не работает', () async {
      final id = await createQuest();
      me = 'organizer';
      final old = await repo.arrivalCode(id);
      final fresh = await repo.rotateArrivalCode(id);
      expect(fresh, isNot(old));
      expect(fresh, hasLength(8));
      me = 'lev';
      expect(repo.confirmArrival(questId: id, code: old), rule('quest_bad_code'));
    });

    test('код видит только организатор', () async {
      final id = await createQuest();
      me = 'lev';
      expect(repo.arrivalCode(id), rule('quest_not_yours'));
    });
  });

  group('приватность участий (п. 43, 44)', () {
    test('организатор видит всех, участник — соучастников, чужой — никого', () async {
      final id = await createQuest(limit: 5);
      me = 'lev';
      await repo.requestJoin(id);
      me = 'alex';
      await repo.requestJoin(id);
      me = 'organizer';
      final list = await repo.loadParticipants(id);
      expect(list, hasLength(2));
      await repo.decideRequest(
        participationId: list.firstWhere((p) => p.profileId == 'lev').id,
        approved: true,
      );

      me = 'lev';
      final seenByLev = await repo.loadParticipants(id);
      // Заявка alex ещё не одобрена — lev её не видит.
      expect(seenByLev.map((p) => p.profileId), ['lev']);

      me = 'stranger';
      expect(await repo.loadParticipants(id), isEmpty);
      // А на карточке виден только счётчик.
      expect((await repo.loadQuest(id))!.occupancy, '1/5');
    });

    test('«мои квесты» — только свои участия', () async {
      final id = await createQuest();
      me = 'lev';
      await repo.requestJoin(id);
      me = 'stranger';
      expect(await repo.myQuests(), isEmpty);
    });
  });

  group('жизнь квеста на карте', () {
    test('завершённый квест без моментов с карты уходит', () async {
      final id = await createQuest();
      await repo.finishQuest(id);
      final nearby = await repo.loadNearby(latitude: 43.58, longitude: 39.72);
      expect(nearby.where((q) => q.id == id), isEmpty);
    });

    test('завершённый квест с моментом виден ещё сутки (п. 42)', () async {
      final id = await createQuest();
      repo.addMoment(
        id,
        QuestMoment(postId: 'p1', authorId: 'lev', authorName: 'Лев', createdAt: now),
      );
      await repo.finishQuest(id);

      final soon = await repo.loadNearby(latitude: 43.58, longitude: 39.72);
      final trail = soon.singleWhere((q) => q.id == id);
      expect(trail.isTrail, isTrue);
      expect(trail.acceptsRequests, isFalse);

      now = now.add(const Duration(hours: 25));
      final later = await repo.loadNearby(latitude: 43.58, longitude: 39.72);
      expect(later.where((q) => q.id == id), isEmpty);
    });

    test('истёкший по времени квест не принимает заявок', () async {
      final id = await createQuest(endsAt: now.add(const Duration(hours: 1)));
      now = now.add(const Duration(hours: 2));
      me = 'lev';
      expect(repo.requestJoin(id), rule('quest_closed'));
      expect((await repo.loadQuest(id))!.status, QuestStatus.finished);
    });

    test('долгоживущий квест без окончания идёт днями (п. 35)', () async {
      final id = await createQuest();
      now = now.add(const Duration(days: 3));
      me = 'sergey';
      expect(await repo.requestJoin(id), QuestParticipationStatus.approved);
    });

    test('после завершения участия можно вернуться в долгий квест', () async {
      final id = await createQuest();
      me = 'lev';
      await repo.requestJoin(id);
      await repo.completeParticipation(id);
      expect(await repo.requestJoin(id), QuestParticipationStatus.approved);
    });
  });

  test('коды отказов превращаются в понятный текст', () {
    expect(friendlyError(const RuleViolation('quest_full')), 'Мест больше нет');
    // Так выглядит отказ сервера: код внутри текста PostgrestException.
    expect(
      friendlyError(Exception('PostgrestException(message: quest_bad_code, code: P0001)')),
      'Код не подходит. Уточните его у организатора',
    );
    // Похожие коды не путаются.
    expect(
      friendlyError(Exception('quest_request_not_found')),
      'Заявка не найдена',
    );
    expect(normalizeArrivalCode(' ab-cd 23 45 '), 'ABCD2345');
  });
}
