import '../domain/entities/event.dart';
import '../domain/repositories/events_repository.dart';

/// Лента событий на моках, пока Supabase не поднят — тот же приём, что и
/// в LocalFeedRepository: изменения живут до перезапуска, чтобы можно было
/// пройти сценарий целиком.
class LocalEventsRepository implements EventsRepository {
  LocalEventsRepository({
    required this.currentUserId,
    required this.currentUserName,
  });

  final String Function() currentUserId;
  final String Function() currentUserName;

  late final List<Event> _events = List.of(_seed);
  var _nextId = 0;

  @override
  Future<List<Event>> loadEvents({int limit = 50}) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final sorted = List.of(_events)
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    return sorted.take(limit).toList(growable: false);
  }

  @override
  Future<Event> createEvent({
    required String title,
    required DateTime startsAt,
    String? description,
    DateTime? endsAt,
    String? placeTitle,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final event = Event(
      id: 'local-event-${_nextId++}',
      authorId: currentUserId(),
      authorName: currentUserName(),
      title: title.trim(),
      description: description?.trim(),
      startsAt: startsAt,
      endsAt: endsAt,
      placeTitle: placeTitle,
      createdAt: DateTime.now(),
    );
    _events.add(event);
    return event;
  }

  @override
  Future<Event> toggleJoin(Event event) async {
    final joined = !event.joinedByMe;
    final updated = event.copyWith(
      joinedByMe: joined,
      participantCount: event.participantCount + (joined ? 1 : -1),
    );
    final index = _events.indexWhere((item) => item.id == event.id);
    if (index != -1) _events[index] = updated;
    return updated;
  }

  @override
  Future<void> deleteEvent(String eventId) async {
    _events.removeWhere((event) => event.id == eventId);
  }

  static final _seed = <Event>[
    Event(
      id: 'seed-event-1',
      authorId: 'person-3',
      authorName: 'Саша',
      title: 'Утренний забег вдоль моря',
      description: 'Стартуем от Театральной, темп спокойный, компанию найдём по пути.',
      placeTitle: 'Театральная площадь',
      startsAt: DateTime.now().add(const Duration(days: 1, hours: 7)),
      createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      participantCount: 5,
    ),
    Event(
      id: 'seed-event-2',
      authorId: 'person-6',
      authorName: 'Ника',
      title: 'Вечер настольных игр',
      description: 'Собираемся у Площади Искусств, игр много — приносить не обязательно.',
      placeTitle: 'Площадь Искусств',
      startsAt: DateTime.now().add(const Duration(days: 3, hours: 19)),
      createdAt: DateTime.now().subtract(const Duration(hours: 8)),
      participantCount: 11,
    ),
  ];
}
