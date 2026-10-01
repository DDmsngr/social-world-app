import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/channels_repository.dart';

final channelsRepositoryProvider = Provider<ChannelsRepository>((ref) {
  ref.keepAlive();
  return ChannelsRepository(Supabase.instance.client);
});

final channelInfoProvider = FutureProvider.autoDispose.family<ChannelInfo?, String>(
  (ref, channelId) => ref.watch(channelsRepositoryProvider).info(channelId),
);

/// Лента канала: новые сверху списка данных (на экране — снизу, как в
/// Telegram), догрузка старых страницами.
class ChannelPostsController extends AsyncNotifier<List<ChannelPost>> {
  ChannelPostsController(this.channelId);

  final String channelId;
  bool _hasMore = true;
  bool _loadingMore = false;

  bool get hasMore => _hasMore;

  @override
  Future<List<ChannelPost>> build() async {
    final page = await ref.watch(channelsRepositoryProvider).posts(channelId);
    _hasMore = page.length >= 30;
    return page;
  }

  /// Подтянуть свежие посты, не теряя уже догруженную историю.
  Future<void> refreshTop() async {
    final current = state.value;
    if (current == null) {
      ref.invalidateSelf();
      return;
    }
    final fresh = await ref.read(channelsRepositoryProvider).posts(channelId);
    final known = {for (final p in fresh) p.message.id};
    final oldest = fresh.isEmpty ? null : fresh.last.message.sentAt;
    state = AsyncValue.data([
      ...fresh,
      for (final p in current)
        if (!known.contains(p.message.id) &&
            (oldest == null || p.message.sentAt.isBefore(oldest)))
          p,
    ]);
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (!_hasMore || _loadingMore || current == null || current.isEmpty) return;
    _loadingMore = true;
    try {
      final page = await ref
          .read(channelsRepositoryProvider)
          .posts(channelId, before: current.last.message.sentAt);
      _hasMore = page.length >= 30;
      state = AsyncValue.data([...current, ...page]);
    } finally {
      _loadingMore = false;
    }
  }

  void bumpComments(String messageId, int delta) {
    final current = state.value;
    if (current == null) return;
    state = AsyncValue.data([
      for (final p in current)
        p.message.id == messageId ? p.withComments(p.commentCount + delta) : p,
    ]);
  }

  void remove(String messageId) {
    final current = state.value;
    if (current == null) return;
    state = AsyncValue.data([
      for (final p in current)
        if (p.message.id != messageId) p,
    ]);
  }
}

final channelPostsProvider = AsyncNotifierProvider.autoDispose
    .family<ChannelPostsController, List<ChannelPost>, String>(
      ChannelPostsController.new,
    );
