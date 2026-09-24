import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/entities/need_request.dart';
import '../domain/repositories/needs_repository.dart';

/// Через функции миграции 0023: таблица просьб для прямых запросов закрыта,
/// а точку чужой просьбы сервер отдаёт размытой.
class SupabaseNeedsRepository implements NeedsRepository {
  SupabaseNeedsRepository(this._client);

  final SupabaseClient _client;

  Future<List<NeedRequest>> _list(Map<String, dynamic> params) async {
    final rows = await _client.rpc('city_needs', params: params) as List<dynamic>;
    return [for (final row in rows) needFromRow(row as Map<String, dynamic>)];
  }

  @override
  Future<List<NeedRequest>> loadNearby({
    required double latitude,
    required double longitude,
    int radiusMeters = 5000,
  }) => _list({
    'in_lat': latitude,
    'in_lng': longitude,
    'in_radius_m': radiusMeters,
  });

  @override
  Future<NeedRequest?> loadNeed(String needId) async {
    final rows = await _list({'in_need': needId});
    return rows.isEmpty ? null : rows.first;
  }

  @override
  Future<List<NeedRequest>> myNeeds() => _list({'in_mine': true});

  @override
  Future<String> createNeed({
    required String text,
    String? placeId,
    String? placeTitle,
    double? latitude,
    double? longitude,
    DateTime? expiresAt,
  }) async {
    final id = await _client.rpc(
      'create_need',
      params: {
        'in_body': text.trim(),
        'in_place_id': placeId,
        'in_place_title': placeTitle,
        'in_lat': latitude,
        'in_lng': longitude,
        'in_expires_at': expiresAt?.toUtc().toIso8601String(),
      },
    );
    return id as String;
  }

  @override
  Future<void> closeNeed(String needId) =>
      _client.rpc('close_need', params: {'in_need': needId});

  @override
  Future<void> deleteNeed(String needId) =>
      _client.rpc('delete_need', params: {'in_need': needId});

  @override
  Future<void> respond(String needId, {String? text}) => _client.rpc(
    'need_respond',
    params: {'in_need': needId, 'in_body': text},
  );

  @override
  Future<void> withdrawResponse(String needId) =>
      _client.rpc('need_withdraw_response', params: {'in_need': needId});

  @override
  Future<List<NeedResponse>> loadResponses(String needId) async {
    final rows = await _client.rpc(
      'need_responses_list',
      params: {'in_need': needId},
    ) as List<dynamic>;
    return [
      for (final raw in rows)
        NeedResponse(
          id: (raw as Map<String, dynamic>)['id'] as String,
          authorId: raw['author_id'] as String,
          authorName: (raw['display_name'] as String?) ?? 'Без имени',
          authorAvatarUrl: raw['avatar_url'] as String?,
          text: raw['body'] as String?,
          createdAt: DateTime.parse(raw['created_at'] as String),
        ),
    ];
  }
}

NeedRequest needFromRow(Map<String, dynamic> row) => NeedRequest(
  id: row['id'] as String,
  authorId: row['author_id'] as String,
  authorName: (row['author_name'] as String?) ?? 'Без имени',
  authorAvatarUrl: row['avatar_url'] as String?,
  text: row['body'] as String,
  placeId: row['place_id'] as String?,
  placeTitle: row['place_title'] as String?,
  latitude: (row['latitude'] as num?)?.toDouble(),
  longitude: (row['longitude'] as num?)?.toDouble(),
  status: NeedStatus.parse(row['status'] as String?),
  expiresAt: row['expires_at'] is String
      ? DateTime.parse(row['expires_at'] as String)
      : null,
  createdAt: DateTime.parse(row['created_at'] as String),
  replyCount: (row['response_count'] as num?)?.toInt() ?? 0,
  respondedByMe: row['responded_by_me'] as bool? ?? false,
);
