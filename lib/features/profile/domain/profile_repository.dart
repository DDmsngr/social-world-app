import 'profile_models.dart';

abstract interface class ProfileRepository {
  /// `null` — профиля нет либо он недоступен (человек заблокировал меня).
  Future<UserProfile?> loadProfile(String userId);

  /// Премиум ли я сейчас. Видеоаватар (кружок вместо фото) ставит только
  /// премиум; решение принимает сервер, клиент лишь прячет кнопку.
  Future<bool> isPremium();

  /// Видеоаватар из файла на устройстве; null — убрать.
  Future<void> setAvatarVideo(String? localPath);

  Future<void> setFollow(String userId, {required bool follow});

  /// Блокировка и «скрыть публикации» — одна операция с разным [kind]: при
  /// блокировке сервер дополнительно разрывает подписки в обе стороны.
  Future<void> setBlock(String userId, BlockKind kind);

  Future<void> clearBlock(String userId);

  Future<List<BlockedUser>> loadBlocks();

  /// Поиск людей по имени (от двух символов).
  Future<List<ProfileHit>> searchProfiles(String query);

  /// Подписчики или подписки человека. Заблокированные пары сервер не отдаёт.
  Future<List<ProfileHit>> loadFollowList(
    String userId,
    FollowList list, {
    int offset = 0,
  });
}
