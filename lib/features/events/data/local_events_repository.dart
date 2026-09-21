import '../../../core/permissions/content_permissions.dart';
import '../domain/entities/event.dart';
import '../domain/entities/event_route.dart';
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
  final _participants = <String, List<EventParticipant>>{};
  var _nextId = 0;

  @override
  Future<List<Event>> loadEvents({int limit = 50}) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final sorted = List.of(_events)
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    return sorted.take(limit).toList(growable: false);
  }

  @override
  Future<Event?> loadEvent(String eventId) async {
    for (final event in _events) {
      if (event.id == eventId) return event;
    }
    return null;
  }

  @override
  Future<Event> createEvent({
    required String title,
    required DateTime startsAt,
    String? description,
    DateTime? endsAt,
    String? placeId,
    String? placeTitle,
    List<EventRoutePoint> routePoints = const [],
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
      placeId: placeId,
      placeTitle: placeTitle,
      routePoints: routePoints,
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

    final list = _participants.putIfAbsent(event.id, () => []);
    list.removeWhere((p) => p.profileId == currentUserId());
    if (joined) {
      list.add(
        EventParticipant(
          profileId: currentUserId(),
          displayName: currentUserName(),
        ),
      );
    }
    return updated;
  }

  @override
  Future<List<EventParticipant>> loadParticipants(String eventId) async {
    final own = _participants[eventId] ?? const <EventParticipant>[];
    // К живым участникам добавляем автора события: он идёт всегда.
    final event = await loadEvent(eventId);
    return [
      if (event != null &&
          !own.any((p) => p.profileId == event.authorId))
        EventParticipant(
          profileId: event.authorId,
          displayName: event.authorName,
        ),
      ...own,
    ];
  }

  @override
  Future<void> deleteEvent(String eventId) async {
    final index = _events.indexWhere((event) => event.id == eventId);
    if (index == -1) return;
    ContentPermissions(
      viewerId: currentUserId(),
      ownerId: _events[index].authorId,
    ).requireOwner();
    _events.removeAt(index);
  }

  static final _seed = <Event>[
    Event(
      id: 'seed-event-1',
      authorId: 'person-3',
      authorName: 'Саша',
      title: 'Утренний забег вдоль моря',
      description: 'Стартуем от Театральной, темп спокойный, компанию найдём по пути.',
      placeId: 'theatre-square',
      placeTitle: 'Театральная площадь',
      latitude: 43.5789,
      longitude: 39.7232,
      startsAt: DateTime.now().add(const Duration(hours: 5)),
      createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      participantCount: 5,
      routePoints: const [
        EventRoutePoint(
          latitude: 43.5789,
          longitude: 39.7232,
          title: 'Театральная площадь',
        ),
        EventRoutePoint(
          latitude: 43.5740,
          longitude: 39.7289,
          title: 'Приморская набережная',
        ),
        EventRoutePoint(
          latitude: 43.5689,
          longitude: 39.7258,
          title: 'Зимний театр',
        ),
      ],
    ),
    Event(
      id: 'seed-event-2',
      authorId: 'person-6',
      authorName: 'Ника',
      title: 'Вечер настольных игр',
      description: 'Собираемся у Площади Искусств, игр много — приносить не обязательно.',
      placeId: 'art-square',
      placeTitle: 'Площадь Искусств',
      latitude: 43.5752,
      longitude: 39.7246,
      startsAt: DateTime.now().add(const Duration(days: 3, hours: 19)),
      createdAt: DateTime.now().subtract(const Duration(hours: 8)),
      participantCount: 11,
    ),
  ];
}
