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
  });

  /// Возвращает событие с обновлённым счётчиком, чтобы экран не пересчитывал сам.
  Future<Event> toggleJoin(Event event);

  Future<List<EventParticipant>> loadParticipants(String eventId);

  /// Отмена события организатором. Участники получают уведомление.
  Future<void> deleteEvent(String eventId);
}
