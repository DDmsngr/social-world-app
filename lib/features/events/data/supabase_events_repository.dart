import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/entities/event.dart';
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
  Future<Event> createEvent({
    required String title,
    required DateTime startsAt,
    String? description,
    DateTime? endsAt,
    String? placeTitle,
  }) async {
    final placeId = placeTitle == null
        ? null
        : await _client
              .from('places')
              .select('id')
              .eq('title', placeTitle)
              .maybeSingle()
              .then((row) => row?['id'] as String?);

    final row = await _client
        .from('events')
        .insert({
          'author_id': _userId,
          'title': title.trim(),
          'description': description?.trim(),
          'starts_at': startsAt.toUtc().toIso8601String(),
          'ends_at': endsAt?.toUtc().toIso8601String(),
          'place_id': placeId,
        })
        .select()
        .single();

    final profile = await _client
        .from('profiles')
        .select('display_name,avatar_url')
        .eq('id', _userId)
        .single();

    return Event(
      id: row['id'] as String,
      authorId: _userId,
      authorName: (profile['display_name'] as String?) ?? 'Без имени',
      authorAvatarUrl: profile['avatar_url'] as String?,
      title: row['title'] as String,
      description: row['description'] as String?,
      startsAt: DateTime.parse(row['starts_at'] as String),
      endsAt: _parseNullable(row['ends_at']),
      placeTitle: placeTitle,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }

  @override
  Future<Event> toggleJoin(Event event) async {
    if (event.joinedByMe) {
      await _client.from('event_participants').delete().match({
        'event_id': event.id,
        'profile_id': _userId,
      });
    } else {
      await _client.from('event_participants').insert({
        'event_id': event.id,
        'profile_id': _userId,
      });
    }

    final joined = !event.joinedByMe;
    return event.copyWith(
      joinedByMe: joined,
      participantCount: event.participantCount + (joined ? 1 : -1),
    );
  }

  @override
  Future<void> deleteEvent(String eventId) =>
      _client.from('events').delete().eq('id', eventId);

  Event _fromRow(Map<String, dynamic> row) => Event(
    id: row['id'] as String,
    authorId: row['author_id'] as String,
    authorName: (row['author_name'] as String?) ?? 'Без имени',
    authorAvatarUrl: row['avatar_url'] as String?,
    title: row['title'] as String,
    description: row['description'] as String?,
    startsAt: DateTime.parse(row['starts_at'] as String),
    endsAt: _parseNullable(row['ends_at']),
    placeTitle: row['place_title'] as String?,
    coverUrl: row['cover_url'] as String?,
    createdAt: DateTime.parse(row['created_at'] as String),
    participantCount: (row['participant_count'] as num?)?.toInt() ?? 0,
    joinedByMe: row['joined_by_me'] as bool? ?? false,
  );

  DateTime? _parseNullable(dynamic raw) =>
      raw is String ? DateTime.parse(raw) : null;
}
