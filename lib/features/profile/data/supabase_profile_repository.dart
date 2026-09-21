import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/profile_models.dart';
import '../domain/profile_repository.dart';

class SupabaseProfileRepository implements ProfileRepository {
  SupabaseProfileRepository(this._client);

  final SupabaseClient _client;

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw const AuthException('Нет активной сессии');
    return id;
  }

  @override
  Future<UserProfile?> loadProfile(String userId) async {
    final rows = await _client.rpc(
      'profile_card',
      params: {'in_profile': userId},
    ) as List<dynamic>;
    if (rows.isEmpty) return null;

    final row = rows.first as Map<String, dynamic>;
    return UserProfile(
      id: row['id'] as String,
      displayName: (row['display_name'] as String?) ?? 'Без имени',
      avatarUrl: row['avatar_url'] as String?,
      bio: row['bio'] as String?,
      city: row['city'] as String?,
      socialScore: (row['social_score'] as num?)?.toInt() ?? 0,
      followerCount: (row['follower_count'] as num?)?.toInt() ?? 0,
      followingCount: (row['following_count'] as num?)?.toInt() ?? 0,
      followedByMe: row['followed_by_me'] as bool? ?? false,
      blockKind: BlockKind.parse(row['block_kind']),
    );
  }

  @override
  Future<void> setFollow(String userId, {required bool follow}) async {
    final me = _userId;
    if (follow) {
      await _client.from('follows').upsert({
        'follower_id': me,
        'target_type': 'profile',
        'target_id': userId,
      }, onConflict: 'follower_id,target_type,target_id');
    } else {
      await _client.from('follows').delete().match({
        'follower_id': me,
        'target_type': 'profile',
        'target_id': userId,
      });
    }
  }

  @override
  Future<void> setBlock(String userId, BlockKind kind) => _client.rpc(
    'set_user_block',
    params: {'in_user': userId, 'in_kind': kind.name},
  );

  @override
  Future<void> clearBlock(String userId) =>
      _client.rpc('clear_user_block', params: {'in_user': userId});

  @override
  Future<List<BlockedUser>> loadBlocks() async {
    final rows = await _client.rpc('my_blocks') as List<dynamic>;
    return [
      for (final raw in rows)
        BlockedUser(
          userId: (raw as Map<String, dynamic>)['user_id'] as String,
          displayName: (raw['display_name'] as String?) ?? 'Без имени',
          avatarUrl: raw['avatar_url'] as String?,
          kind: BlockKind.parse(raw['kind']) ?? BlockKind.block,
        ),
    ];
  }

  @override
  Future<List<ProfileHit>> searchProfiles(String query) async {
    if (query.trim().length < 2) return const [];
    final rows = await _client.rpc(
      'search_profiles',
      params: {'in_query': query.trim(), 'in_limit': 8},
    ) as List<dynamic>;
    return [
      for (final raw in rows)
        ProfileHit(
          id: (raw as Map<String, dynamic>)['id'] as String,
          displayName: (raw['display_name'] as String?) ?? 'Без имени',
          avatarUrl: raw['avatar_url'] as String?,
        ),
    ];
  }
}
