import '../entities/event.dart';
import '../entities/event_route.dart';

abstract interface class EventsRepository {
  Future<List<Event>> loadEvents({int limit = 50});

  /// Одно событие по id — для ссылок и уведомлений, когда его нет в уже
  /// загруженном списке. `null` — удалено, отменено или недоступно.
  Future<Event?> loadEvent(String eventId);

  /// [placeId]/[placeTitle] — см. пояснение в FeedRepository.createPost:
  /// резолвить id по названию нельзя, названия мест не уникальны.
  /// [routePoints] сохраняются вместе с событием одной записью.
  Future<Event> createEvent({
    required String title,
    required DateTime startsAt,
    String? description,
    DateTime? endsAt,
    String? placeId,
    String? placeTitle,
    List<EventRoutePoint> routePoints = const [],
    EventJoinMode joinMode = EventJoinMode.free,
    int? maxParticipants,
  });

  /// Возвращает событие с обновлённым счётчиком, чтобы экран не пересчитывал сам.
  Future<Event> toggleJoin(Event event);

  Future<List<EventParticipant>> loadParticipants(String eventId);

  /// Отмена события организатором. Участники получают уведомление.
  Future<void> deleteEvent(String eventId);

  /// Просьба принять на встречу «по запросу»: человек пишет о себе.
  Future<void> requestJoin(String eventId, {required String about, String? message});

  Future<void> withdrawRequest(String eventId);

  /// Запросы к моей встрече: сначала ожидающие (только организатору).
  Future<List<JoinRequest>> loadRequests(String eventId);

  /// Принять или отклонить запрос; принятый сразу становится участником.
  Future<void> decideRequest(String requestId, {required bool approve});

  /// Друзья, которых можно позвать (ещё не участвуют).
  Future<List<InviteCandidate>> loadInviteCandidates(String eventId, {String? query});

  /// Позвать людей: они сразу становятся участниками. Возвращает, сколько
  /// добавлено и сколько не поместилось из-за лимита.
  Future<({int added, int full})> invite(String eventId, List<String> profileIds);
}
