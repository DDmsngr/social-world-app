import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/channels_repository.dart';

/// Где человек остановился в канале: время самого нового из показанных ему
/// постов. Хранится на устройстве и переживает закрытие приложения.
abstract final class ChannelSeen {
  static String _key(String channelId) => 'channel_seen_$channelId';

  static Future<DateTime?> load(String channelId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(channelId));
      return raw == null ? null : DateTime.tryParse(raw);
    } catch (_) {
      return null;
    }
  }

  /// Запоминает только движение вперёд: прокрутка к старым постам место не
  /// сбрасывает.
  static Future<void> save(String channelId, DateTime time) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final old = DateTime.tryParse(prefs.getString(_key(channelId)) ?? '');
      if (old != null && !time.isAfter(old)) return;
      await prefs.setString(_key(channelId), time.toUtc().toIso8601String());
    } catch (_) {}
  }
}

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

  /// Время последнего поста, который человек видел при прошлом заходе, если
  /// после него есть новые. Лента открывается на этом месте, а новые посты
  /// лежат ниже. null — смотреть сначала нечего: открываем на самом новом.
  DateTime? anchor;

  bool get hasMore => _hasMore;

  @override
  Future<List<ChannelPost>> build() async {
    final repo = ref.watch(channelsRepositoryProvider);
    final seen = await ChannelSeen.load(channelId);
    var items = await repo.posts(channelId);
    _hasMore = items.length >= 30;
    anchor = null;
    if (seen != null && items.isNotEmpty && items.first.message.sentAt.isAfter(seen)) {
      // Есть непрочитанное: докручиваем историю до места, где остановились
      // (с запасом по числу страниц, чтобы не качать весь канал).
      while (_hasMore && items.last.message.sentAt.isAfter(seen) && items.length < 400) {
        final page = await repo.posts(channelId, before: items.last.message.sentAt);
        _hasMore = page.length >= 30;
        items = [...items, ...page];
      }
      if (!items.last.message.sentAt.isAfter(seen)) anchor = seen;
    }
    return items;
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
