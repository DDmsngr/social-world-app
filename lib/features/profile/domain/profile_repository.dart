import 'profile_models.dart';

abstract interface class ProfileRepository {
  /// `null` — профиля нет либо он недоступен (человек заблокировал меня).
  Future<UserProfile?> loadProfile(String userId);

  Future<void> setFollow(String userId, {required bool follow});

  /// Блокировка и «скрыть публикации» — одна операция с разным [kind]: при
  /// блокировке сервер дополнительно разрывает подписки в обе стороны.
  Future<void> setBlock(String userId, BlockKind kind);

  Future<void> clearBlock(String userId);

  Future<List<BlockedUser>> loadBlocks();

  /// Поиск людей по имени (от двух символов).
  Future<List<ProfileHit>> searchProfiles(String query);
}
