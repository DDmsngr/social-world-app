import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/env.dart';
import '../../../../core/debug/app_log.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../events/presentation/providers/events_providers.dart';
import '../../../feed/domain/entities/post.dart';
import '../../../feed/presentation/providers/feed_providers.dart';
import '../../data/local_profile_repository.dart';
import '../../data/supabase_profile_repository.dart';
import '../../domain/profile_models.dart';
import '../../domain/profile_repository.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  // keepAlive: у заглушки подписки и блокировки лежат в памяти.
  ref.keepAlive();
  if (!Env.isConfigured) {
    return LocalProfileRepository(
      currentUserId: () => ref.read(currentUserProvider)?.id ?? 'local-user',
    );
  }
  return SupabaseProfileRepository(Supabase.instance.client);
});

/// Карточка профиля. autoDispose + invalidate после подписки/блокировки:
/// экран всегда показывает то, что записано на сервере, а не догадку.
final userProfileProvider = FutureProvider.autoDispose
    .family<UserProfile?, String>((ref, userId) {
      return ref.watch(profileRepositoryProvider).loadProfile(userId);
    });

/// Публикации одного человека — вкладка чужого и своего профиля.
final userPostsProvider = FutureProvider.autoDispose
    .family<List<Post>, String>((ref, userId) {
      return ref.watch(feedRepositoryProvider).loadFeed(authorId: userId);
    });

/// Кого я заблокировал или скрыл. Список нужен не только экрану настроек:
/// по нему ещё и фильтруются лента, события, комментарии и карта, пока сервер
/// не вернул свежие данные.
class BlocksController extends AsyncNotifier<Map<String, BlockedUser>> {
  @override
  Future<Map<String, BlockedUser>> build() async {
    ref.keepAlive();
    if (ref.watch(currentUserProvider) == null) return const {};
    try {
      final blocks = await ref.watch(profileRepositoryProvider).loadBlocks();
      return {for (final block in blocks) block.userId: block};
    } catch (error) {
      // Сервер и сам не отдаёт контент заблокированных; этот список лишь
      // ускоряет скрытие на экране. Без него приложение должно работать.
      AppLog.add('Список блокировок не загрузился: $error');
      return const {};
    }
  }

  Set<String> get ids => state.value?.keys.toSet() ?? const {};

  Future<void> block(
    String userId,
    BlockKind kind, {
    required String displayName,
    String? avatarUrl,
  }) async {
    await ref.read(profileRepositoryProvider).setBlock(userId, kind);
    state = AsyncData({
      ...?state.value,
      userId: BlockedUser(
        userId: userId,
        displayName: displayName,
        avatarUrl: avatarUrl,
        kind: kind,
      ),
    });
    // Контент человека уходит из уже загруженных списков сразу.
    ref.read(feedProvider.notifier).hide(userId);
    ref.read(eventsProvider.notifier).hide(userId);
    ref.invalidate(userProfileProvider(userId));
  }

  Future<void> unblock(String userId) async {
    await ref.read(profileRepositoryProvider).clearBlock(userId);
    state = AsyncData({...?state.value}..remove(userId));
    ref.invalidate(userProfileProvider(userId));
    // Возвращаем в ленту то, что было скрыто.
    try {
      await ref.read(feedProvider.notifier).refresh();
      await ref.read(eventsProvider.notifier).refresh();
    } catch (error) {
      AppLog.add('Обновление после разблокировки: $error');
    }
  }
}

final blocksProvider =
    AsyncNotifierProvider<BlocksController, Map<String, BlockedUser>>(
      BlocksController.new,
    );
