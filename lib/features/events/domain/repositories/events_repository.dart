import '../entities/event.dart';

abstract interface class EventsRepository {
  Future<List<Event>> loadEvents({int limit = 50});

  Future<Event> createEvent({
    required String title,
    required DateTime startsAt,
    String? description,
    DateTime? endsAt,
    String? placeTitle,
  });

  /// Возвращает событие с обновлённым счётчиком, чтобы экран не пересчитывал сам.
  Future<Event> toggleJoin(Event event);

  Future<void> deleteEvent(String eventId);
}
