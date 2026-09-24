import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/core/errors/rule_violation.dart';
import 'package:social_world/features/needs/data/local_needs_repository.dart';
import 'package:social_world/features/needs/domain/entities/need_request.dart';

// Правила «Мне надо» из миграции 0023: неделя по умолчанию, на своё не
// откликнуться, закрытая просьба с карты уходит.
void main() {
  late String me;
  late DateTime now;
  late LocalNeedsRepository repo;

  setUp(() {
    me = 'nika';
    now = DateTime(2026, 9, 25, 12);
    repo = LocalNeedsRepository(
      currentUserId: () => me,
      currentUserName: () => me,
      clock: () => now,
      seed: false,
    );
  });

  Matcher rule(String code) =>
      throwsA(isA<RuleViolation>().having((e) => e.code, 'code', code));

  Future<String> create({DateTime? expiresAt}) => repo.createNeed(
    text: 'Повесить телевизор',
    latitude: 43.58,
    longitude: 39.72,
    expiresAt: expiresAt,
  );

  test('без срока просьба живёт неделю', () async {
    final id = await create();
    final need = (await repo.loadNeed(id))!;
    expect(need.expiresAt, now.add(const Duration(days: 7)));
    expect(need.isVisible, isTrue);
  });

  test('видна на карте рядом, закрытая — уже нет', () async {
    final id = await create();
    expect(
      (await repo.loadNearby(latitude: 43.58, longitude: 39.72)).map((n) => n.id),
      [id],
    );
    await repo.closeNeed(id);
    expect(await repo.loadNearby(latitude: 43.58, longitude: 39.72), isEmpty);
    // В «моих» закрытая остаётся.
    expect((await repo.myNeeds()).single.status, NeedStatus.closed);
  });

  test('далеко от центра не видна', () async {
    await create();
    expect(await repo.loadNearby(latitude: 45.0, longitude: 39.0), isEmpty);
  });

  test('отклик: один на человека, повтор обновляет текст', () async {
    final id = await create();
    me = 'sasha';
    await repo.respond(id, text: 'Могу завтра');
    await repo.respond(id, text: 'Могу сегодня');
    final responses = await repo.loadResponses(id);
    expect(responses.single.text, 'Могу сегодня');
    final need = (await repo.loadNeed(id))!;
    expect(need.replyCount, 1);
    expect(need.respondedByMe, isTrue);

    await repo.withdrawResponse(id);
    expect(await repo.loadResponses(id), isEmpty);
  });

  test('на свою просьбу не откликнуться', () async {
    final id = await create();
    expect(repo.respond(id), rule('need_is_yours'));
  });

  test('на закрытую просьбу не откликнуться', () async {
    final id = await create();
    await repo.closeNeed(id);
    me = 'sasha';
    expect(repo.respond(id), rule('need_closed'));
  });

  test('чужую просьбу не закрыть и не удалить', () async {
    final id = await create();
    me = 'sasha';
    expect(repo.closeNeed(id), rule('need_not_yours'));
    expect(repo.deleteNeed(id), rule('need_not_yours'));
  });

  test('срок в прошлом не принимается', () async {
    expect(
      create(expiresAt: now.subtract(const Duration(minutes: 1))),
      rule('need_expired'),
    );
  });
}
