import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/media/media_uploader.dart';
import '../domain/entities/quest.dart';
import '../domain/repositories/quests_repository.dart';

/// Все чтения и записи — через функции миграции 0023: таблицы квестов для
/// прямых запросов закрыты, правила (лимит мест, кто кого одобряет, чьи
/// участия видно) проверяет база.
class SupabaseQuestsRepository implements QuestsRepository {
  SupabaseQuestsRepository(this._client);

  final SupabaseClient _client;

  Future<List<Quest>> _list(Map<String, dynamic> params) async {
    final rows = await _client.rpc('quests_list', params: params) as List<dynamic>;
    return [for (final row in rows) questFromRow(row as Map<String, dynamic>)];
  }

  @override
  Future<List<Quest>> loadNearby({
    required double latitude,
    required double longitude,
    int radiusMeters = 5000,
    DateTime? at,
  }) => _list({
    'in_scope': 'nearby',
    'in_lat': latitude,
    'in_lng': longitude,
    'in_radius_m': radiusMeters,
    'in_at': (at ?? DateTime.now()).toUtc().toIso8601String(),
  });

  @override
  Future<Quest?> loadQuest(String questId) async {
    final rows = await _list({'in_scope': 'one', 'in_quest': questId});
    return rows.isEmpty ? null : rows.first;
  }

  @override
  Future<String> createQuest({
    required String title,
    required DateTime startsAt,
    String? description,
    String? extraInfo,
    String? photoPath,
    DateTime? endsAt,
    String? placeId,
    String? placeTitle,
    double? latitude,
    double? longitude,
    int? maxParticipants,
  }) async {
    // Фото уезжает в хранилище до записи квеста: не будет квеста с битой
    // картинкой, если загрузка сорвётся.
    final photoUrl = photoPath == null
        ? null
        : await MediaUploader(_client, bucket: 'post-media').upload(photoPath);

    final id = await _client.rpc(
      'create_quest',
      params: {
        'in_title': title.trim(),
        'in_starts_at': startsAt.toUtc().toIso8601String(),
        'in_description': description,
        'in_extra_info': extraInfo,
        'in_photo_url': photoUrl,
        'in_place_id': placeId,
        'in_place_title': placeTitle,
        'in_lat': latitude,
        'in_lng': longitude,
        'in_ends_at': endsAt?.toUtc().toIso8601String(),
        'in_max_participants': maxParticipants,
      },
    );
    return id as String;
  }

  @override
  Future<QuestParticipationStatus> requestJoin(String questId) async {
    final status = await _client.rpc(
      'quest_request_join',
      params: {'in_quest': questId},
    );
    return QuestParticipationStatus.parse(status as String?);
  }

  @override
  Future<void> withdraw(String questId) =>
      _client.rpc('quest_withdraw', params: {'in_quest': questId});

  @override
  Future<void> completeParticipation(String questId) =>
      _client.rpc('quest_complete', params: {'in_quest': questId});

  @override
  Future<QuestParticipationStatus> confirmArrival({
    required String questId,
    required String code,
  }) async {
    final status = await _client.rpc(
      'quest_confirm_arrival',
      params: {'in_quest': questId, 'in_code': code},
    );
    return QuestParticipationStatus.parse(status as String?);
  }

  @override
  Future<List<QuestParticipation>> loadParticipants(String questId) async {
    final rows = await _client.rpc(
      'quest_participants',
      params: {'in_quest': questId},
    ) as List<dynamic>;
    return [
      for (final raw in rows)
        QuestParticipation(
          id: (raw as Map<String, dynamic>)['id'] as String,
          questId: questId,
          profileId: raw['profile_id'] as String,
          displayName: (raw['display_name'] as String?) ?? 'Без имени',
          avatarUrl: raw['avatar_url'] as String?,
          socialScore: (raw['social_score'] as num?)?.toInt() ?? 0,
          status: QuestParticipationStatus.parse(raw['status'] as String?),
          requestedAt: DateTime.parse(raw['requested_at'] as String),
          arrivedAt: _date(raw['arrived_at']),
          completedAt: _date(raw['completed_at']),
        ),
    ];
  }

  @override
  Future<void> decideRequest({
    required String participationId,
    required bool approved,
  }) => _client.rpc(
    'quest_decide',
    params: {'in_participation': participationId, 'in_approve': approved},
  );

  @override
  Future<void> removeParticipant(String participationId) => _client.rpc(
    'quest_remove_participant',
    params: {'in_participation': participationId},
  );

  @override
  Future<List<Quest>> myQuests({bool activeOnly = false}) =>
      _list({'in_scope': 'mine', 'in_active_only': activeOnly});

  @override
  Future<List<Quest>> questsIAuthored({bool activeOnly = false}) =>
      _list({'in_scope': 'authored', 'in_active_only': activeOnly});

  @override
  Future<void> finishQuest(String questId) =>
      _client.rpc('quest_finish', params: {'in_quest': questId});

  @override
  Future<void> cancelQuest(String questId) =>
      _client.rpc('quest_cancel', params: {'in_quest': questId});

  @override
  Future<String> arrivalCode(String questId) async =>
      await _client.rpc('quest_arrival_code', params: {'in_quest': questId})
          as String;

  @override
  Future<String> rotateArrivalCode(String questId) async =>
      await _client.rpc('quest_rotate_code', params: {'in_quest': questId})
          as String;

  @override
  Future<List<QuestMoment>> loadMoments(String questId) async {
    final rows = await _client.rpc(
      'quest_moments',
      params: {'in_quest': questId},
    ) as List<dynamic>;
    return [
      for (final raw in rows)
        QuestMoment(
          postId: (raw as Map<String, dynamic>)['post_id'] as String,
          authorId: raw['author_id'] as String,
          authorName: (raw['author_name'] as String?) ?? 'Без имени',
          authorAvatarUrl: raw['avatar_url'] as String?,
          photoUrl: raw['photo_url'] as String?,
          body: raw['body'] as String?,
          createdAt: DateTime.parse(raw['created_at'] as String),
        ),
    ];
  }

  @override
  Future<QuestRulesConsent?> loadRulesConsent() async {
    final rows = await _client.rpc('my_quest_rules_consent') as List<dynamic>;
    if (rows.isEmpty) return null;
    final row = rows.first as Map<String, dynamic>;
    return QuestRulesConsent(
      version: (row['version'] as num).toInt(),
      acceptedAt: DateTime.parse(row['accepted_at'] as String),
    );
  }

  @override
  Future<void> acceptRules(int version) =>
      _client.rpc('accept_quest_rules', params: {'in_version': version});

  static DateTime? _date(dynamic raw) => raw is String ? DateTime.parse(raw) : null;
}

/// Строка `quests_list` → [Quest]. Отдельной функцией, чтобы разбор можно
/// было проверить тестом без сервера.
Quest questFromRow(Map<String, dynamic> row) {
  final myStatus = row['my_status'] as String?;
  return Quest(
    id: row['id'] as String,
    authorId: row['author_id'] as String,
    authorName: (row['author_name'] as String?) ?? 'Без имени',
    authorAvatarUrl: row['avatar_url'] as String?,
    title: row['title'] as String,
    description: row['description'] as String?,
    extraInfo: row['extra_info'] as String?,
    photoUrl: row['photo_url'] as String?,
    placeId: row['place_id'] as String?,
    placeTitle: row['place_title'] as String?,
    latitude: (row['latitude'] as num?)?.toDouble(),
    longitude: (row['longitude'] as num?)?.toDouble(),
    startsAt: DateTime.parse(row['starts_at'] as String),
    endsAt: row['ends_at'] is String ? DateTime.parse(row['ends_at'] as String) : null,
    maxParticipants: (row['max_participants'] as num?)?.toInt(),
    participantCount: (row['participant_count'] as num?)?.toInt() ?? 0,
    status: QuestStatus.parse(row['status'] as String?),
    finishedAt: row['finished_at'] is String
        ? DateTime.parse(row['finished_at'] as String)
        : null,
    myStatus: myStatus == null ? null : QuestParticipationStatus.parse(myStatus),
    momentCount: (row['moment_count'] as num?)?.toInt() ?? 0,
    isTrail: row['is_trail'] as bool? ?? false,
    createdAt: DateTime.parse(row['created_at'] as String),
  );
}
