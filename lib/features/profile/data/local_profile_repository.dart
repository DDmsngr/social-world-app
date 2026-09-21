import '../../../core/permissions/content_permissions.dart';
import '../domain/profile_models.dart';
import '../domain/profile_repository.dart';

/// Профили на моках: те же люди, что стоят на карте и пишут в ленте. Подписки
/// и блокировки живут до перезапуска — этого хватает, чтобы пройти сценарии.
class LocalProfileRepository implements ProfileRepository {
  LocalProfileRepository({required this.currentUserId});

  final String Function() currentUserId;

  final _followed = <String>{};
  final _blocks = <String, BlockKind>{};

  static const _people = <String, String>{
    'person-1': 'Алина',
    'person-2': 'Марк',
    'person-3': 'Саша',
    'person-4': 'Лена',
    'person-5': 'Илья',
    'person-6': 'Ника',
  };

  @override
  Future<UserProfile?> loadProfile(String userId) async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    final name = _people[userId];
    if (name == null) return null;
    return UserProfile(
      id: userId,
      displayName: name,
      bio: 'Живу в Сочи, люблю утро на набережной.',
      city: 'Сочи',
      socialScore: 40 + userId.hashCode.abs() % 90,
      followerCount: 12 + (_followed.contains(userId) ? 1 : 0),
      followingCount: 8,
      followedByMe: _followed.contains(userId),
      blockKind: _blocks[userId],
    );
  }

  @override
  Future<void> setFollow(String userId, {required bool follow}) async {
    if (userId == currentUserId()) {
      throw const PermissionDeniedException('На себя подписаться нельзя');
    }
    follow ? _followed.add(userId) : _followed.remove(userId);
  }

  @override
  Future<void> setBlock(String userId, BlockKind kind) async {
    if (userId == currentUserId()) {
      throw const PermissionDeniedException('Себя заблокировать нельзя');
    }
    _blocks[userId] = kind;
    if (kind == BlockKind.block) _followed.remove(userId);
  }

  @override
  Future<void> clearBlock(String userId) async => _blocks.remove(userId);

  @override
  Future<List<BlockedUser>> loadBlocks() async => [
    for (final entry in _blocks.entries)
      BlockedUser(
        userId: entry.key,
        displayName: _people[entry.key] ?? 'Без имени',
        kind: entry.value,
      ),
  ];

  @override
  Future<List<ProfileHit>> searchProfiles(String query) async {
    final needle = query.trim().toLowerCase();
    if (needle.length < 2) return const [];
    return [
      for (final entry in _people.entries)
        if (entry.value.toLowerCase().contains(needle) &&
            !_blocks.containsKey(entry.key))
          ProfileHit(id: entry.key, displayName: entry.value),
    ];
  }
}
