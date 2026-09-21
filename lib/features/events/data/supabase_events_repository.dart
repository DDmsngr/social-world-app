import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/entities/event.dart';
import '../domain/entities/event_route.dart';
import '../domain/repositories/events_repository.dart';

class SupabaseEventsRepository implements EventsRepository {
  SupabaseEventsRepository(this._client);

  final SupabaseClient _client;

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw const AuthException('Нет активной сессии');
    return id;
  }

  @override
  Future<List<Event>> loadEvents({int limit = 50}) async {
    final rows = await _client.rpc(
      'city_events',
      params: {'in_limit': limit},
    ) as List<dynamic>;

    return rows
        .map((row) => _fromRow(row as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<Event?> loadEvent(String eventId) async {
    final rows = await _client.rpc(
      'city_events',
      params: {'in_event': eventId, 'in_limit': 1},
    ) as List<dynamic>;
    if (rows.isEmpty) return null;
    return _fromRow(rows.first as Map<String, dynamic>);
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
    final userId = _userId;
    final row = await _client
        .from('events')
        .insert({
          'author_id': userId,
          'title': title.trim(),
          'description': description?.trim(),
          'starts_at': startsAt.toUtc().toIso8601String(),
          'ends_at': endsAt?.toUtc().toIso8601String(),
          'place_id': placeId,
          // Маршрут ложится той же записью, что и событие: нет состояния
          // «событие создано, а маршрут потерялся».
          'route_points': [for (final point in routePoints) point.toJson()],
        })
        .select()
        .single();

    // Событие уже создано — падение этого отдельного чтения не должно
    // превращать успешную публикацию в ошибку (см. тот же фикс в постах).
    String? authorName;
    String? authorAvatarUrl;
    try {
      final profile = await _client
          .from('profiles')
          .select('display_name,avatar_url')
          .eq('id', userId)
          .single();
      authorName = profile['display_name'] as String?;
      authorAvatarUrl = profile['avatar_url'] as String?;
    } catch (_) {
      // Молча — событие уже опубликовано.
    }

    return Event(
      id: row['id'] as String,
      authorId: userId,
      authorName: authorName ?? 'Без имени',
      authorAvatarUrl: authorAvatarUrl,
      title: row['title'] as String,
      description: row['description'] as String?,
      startsAt: DateTime.parse(row['starts_at'] as String),
      endsAt: _parseNullable(row['ends_at']),
      placeId: placeId,
      placeTitle: placeTitle,
      routePoints: EventRoutePoint.parseList(row['route_points']),
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }

  @override
  Future<Event> toggleJoin(Event event) async {
    final me = _userId;
    final join = !event.joinedByMe;

    if (join) {
      // Идемпотентно: если запись уже есть (прошлый тап дошёл, а экран
      // об этом не узнал), повтор не падает на дубликате ключа, а просто
      // подтверждает участие.
      await _client.from('event_participants').upsert(
        {'event_id': event.id, 'profile_id': me},
        onConflict: 'event_id,profile_id',
        ignoreDuplicates: true,
      );
    } else {
      await _client.from('event_participants').delete().match({
        'event_id': event.id,
        'profile_id': me,
      });
    }

    // Итог берём у сервера, а не выводим арифметикой: счётчик участников
    // мог измениться за это время у других людей.
    try {
      final fresh = await loadEvent(event.id);
      if (fresh != null) return fresh;
    } catch (_) {
      // Запись прошла — сбой повторного чтения не отменяет участия.
    }
    return event.copyWith(
      joinedByMe: join,
      participantCount: event.participantCount + (join ? 1 : -1),
    );
  }

  @override
  Future<List<EventParticipant>> loadParticipants(String eventId) async {
    final rows = await _client.rpc(
      'event_participants_list',
      params: {'in_event': eventId},
    ) as List<dynamic>;
    return [
      for (final raw in rows)
        EventParticipant(
          profileId: (raw as Map<String, dynamic>)['profile_id'] as String,
          displayName: (raw['display_name'] as String?) ?? 'Без имени',
          avatarUrl: raw['avatar_url'] as String?,
        ),
    ];
  }

  @override
  Future<void> deleteEvent(String eventId) async {
    // eq('author_id') — второй замок поверх RLS: чужое событие не совпадёт
    // с фильтром, и вместо тихого «успеха» придёт пустой результат.
    final deleted = await _client
        .from('events')
        .delete()
        .eq('id', eventId)
        .eq('author_id', _userId)
        .select('id');
    if (deleted.isEmpty) {
      throw const AuthException('Событие не найдено или оно не ваше');
    }
  }

  Event _fromRow(Map<String, dynamic> row) => Event(
    id: row['id'] as String,
    authorId: row['author_id'] as String,
    authorName: (row['author_name'] as String?) ?? 'Без имени',
    authorAvatarUrl: row['avatar_url'] as String?,
    title: row['title'] as String,
    description: row['description'] as String?,
    startsAt: DateTime.parse(row['starts_at'] as String),
    endsAt: _parseNullable(row['ends_at']),
    placeId: row['place_id'] as String?,
    placeTitle: row['place_title'] as String?,
    latitude: (row['place_latitude'] as num?)?.toDouble(),
    longitude: (row['place_longitude'] as num?)?.toDouble(),
    coverUrl: row['cover_url'] as String?,
    routePoints: EventRoutePoint.parseList(row['route_points']),
    createdAt: DateTime.parse(row['created_at'] as String),
    participantCount: (row['participant_count'] as num?)?.toInt() ?? 0,
    joinedByMe: row['joined_by_me'] as bool? ?? false,
  );

  DateTime? _parseNullable(dynamic raw) =>
      raw is String ? DateTime.parse(raw) : null;
}
