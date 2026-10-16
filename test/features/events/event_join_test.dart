import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/features/events/domain/entities/event.dart';
import 'package:social_world/features/events/presentation/widgets/event_join.dart';

Event event({
  EventJoinMode mode = EventJoinMode.free,
  int? max,
  int count = 0,
  bool joined = false,
  String? request,
}) => Event(
  id: 'e',
  authorId: 'a',
  authorName: 'Организатор',
  title: 'Встреча',
  startsAt: DateTime(2030),
  createdAt: DateTime(2026),
  joinMode: mode,
  maxParticipants: max,
  participantCount: count,
  joinedByMe: joined,
  myRequestStatus: request,
);

void main() {
  test('свободный вход: записаться, выйти, мест нет', () {
    expect(eventJoinLabel(event()), 'Участвовать');
    expect(eventJoinLabel(event(joined: true)), 'Вы участвуете');
    final full = event(max: 2, count: 2);
    expect(eventJoinLabel(full), 'Мест нет');
    expect(eventJoinEnabled(full), isFalse);
    // Уже записанный может выйти, даже когда мест нет.
    expect(eventJoinEnabled(event(max: 2, count: 2, joined: true)), isTrue);
  });

  test('по запросу: путь человека от просьбы до отказа', () {
    final m = EventJoinMode.request;
    expect(eventJoinLabel(event(mode: m)), 'Попросить принять');
    expect(eventJoinEnabled(event(mode: m)), isTrue);
    expect(eventJoinLabel(event(mode: m, request: 'pending')), 'Запрос отправлен');
    expect(eventJoinLabel(event(mode: m, request: 'rejected')), 'Организатор отклонил запрос');
    expect(eventJoinEnabled(event(mode: m, request: 'rejected')), isFalse);
    // После отзыва можно попросить снова.
    expect(eventJoinEnabled(event(mode: m, request: 'withdrawn')), isTrue);
    expect(eventJoinLabel(event(mode: m, joined: true, request: 'approved')), 'Вы участвуете');
  });

  test('по приглашению: приглашённый не «записывается» сам', () {
    final m = EventJoinMode.invite;
    expect(eventJoinLabel(event(mode: m, joined: true)), 'Вы приглашены');
    expect(eventJoinEnabled(event(mode: m, joined: true)), isFalse);
    expect(eventJoinEnabled(event(mode: m)), isFalse);
  });

  test('число участников с лимитом и без', () {
    expect(eventPeopleText(event(count: 3)), '3 идёт');
    expect(eventPeopleText(event(count: 3, max: 10)), '3 из 10');
  });

  test('режим разбирается из ответа сервера, незнакомое — свободный вход', () {
    expect(EventJoinMode.parse('request'), EventJoinMode.request);
    expect(EventJoinMode.parse('invite'), EventJoinMode.invite);
    expect(EventJoinMode.parse(null), EventJoinMode.free);
    expect(EventJoinMode.parse('что-то'), EventJoinMode.free);
  });
}
