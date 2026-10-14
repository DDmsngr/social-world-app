import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/debug/app_log.dart';
import '../auth/presentation/providers/auth_providers.dart';
import '../chat/domain/stickers.dart';
import 'data/sticker_repository.dart';

final stickerBackendProvider = Provider<StickerBackend>((ref) {
  ref.keepAlive();
  return SupabaseStickerBackend(Supabase.instance.client);
});

final stickerCacheProvider = Provider<StickerCache>((ref) {
  ref.keepAlive();
  return StickerCache();
});

/// Каталог магазина: все опубликованные паки (и снятые с публикации — их
/// стикеры встречаются в старых сообщениях). Сначала — последний сохранённый
/// на телефоне, сервер догоняет в фоне.
class StickerCatalogController extends AsyncNotifier<StickerCatalog> {
  @override
  Future<StickerCatalog> build() async {
    ref.keepAlive();
    final signedIn = ref.watch(currentUserProvider) != null;
    final cached = await ref.read(stickerCacheProvider).readCatalog();
    if (!signedIn) {
      return cached == null ? StickerCatalog.empty : StickerCatalog.fromJson(cached);
    }
    if (cached != null) {
      // После build: иначе свежий каталог перетёр бы сохранённый результат.
      Future(refresh);
      return StickerCatalog.fromJson(cached);
    }
    return _fetch();
  }

  Future<StickerCatalog> _fetch() async {
    final json = await ref.read(stickerBackendProvider).catalog();
    await ref.read(stickerCacheProvider).writeCatalog(json);
    return StickerCatalog.fromJson(json);
  }

  /// Перечитать с сервера. Без сети остаётся то, что было; ошибка видна,
  /// только если показать нечего.
  Future<void> refresh() async {
    try {
      state = AsyncData(await _fetch());
    } catch (error, stack) {
      AppLog.add('Каталог стикеров не обновился: $error');
      if (state.value == null) state = AsyncError(error, stack);
    }
  }
}

/// Без автоповтора Riverpod: пока он перезапрашивал бы упавший каталог,
/// экран не видел ошибки и не мог показать «Повторить».
Duration? _noRetry(int retryCount, Object error) => null;

final stickerCatalogProvider = AsyncNotifierProvider<StickerCatalogController, StickerCatalog>(
  StickerCatalogController.new,
  retry: _noRetry,
);

/// Каталог для показа: магазин, панель, подсказки. Паки 18+ видят только
/// совершеннолетние. Полный [stickerCatalogProvider] нужен лишь для разбора
/// сообщений.
final visibleStickerCatalogProvider = Provider<AsyncValue<StickerCatalog>>((ref) {
  final catalog = ref.watch(stickerCatalogProvider);
  final adult = ref.watch(currentUserProvider.select((user) => user?.isAdult ?? true));
  return adult ? catalog : catalog.whenData((c) => c.withoutAdult());
});

/// Коллекция текущего пользователя — id паков в порядке вкладок панели.
/// Хранится в базе (user_sticker_packs) и копией на телефоне.
class InstalledStickerPacks extends AsyncNotifier<List<String>> {
  String? _user;

  @override
  Future<List<String>> build() async {
    ref.keepAlive();
    _user = ref.watch(currentUserProvider)?.id;
    final user = _user;
    if (user == null) return const [];
    final cached = await ref.read(stickerCacheProvider).readInstalled(user);
    if (cached != null) {
      Future(refresh);
      return cached;
    }
    return _fetch(user);
  }

  Future<List<String>> _fetch(String user) async {
    final ids = await ref.read(stickerBackendProvider).installed();
    await ref.read(stickerCacheProvider).writeInstalled(user, ids);
    return ids;
  }

  Future<void> refresh() async {
    final user = _user;
    if (user == null) return;
    try {
      state = AsyncData(await _fetch(user));
    } catch (error, stack) {
      AppLog.add('Мои стикеры не обновились: $error');
      if (state.value == null) state = AsyncError(error, stack);
    }
  }

  bool isInstalled(String packId) => state.value?.contains(packId) ?? false;

  /// Сразу в коллекцию, с откатом и ошибкой наружу, если сервер не принял.
  Future<void> install(String packId) async {
    final user = _user;
    if (user == null) throw StateError('Нужно войти в аккаунт');
    final before = state.value ?? const <String>[];
    if (before.contains(packId)) return;
    state = AsyncData([...before, packId]);
    try {
      await ref.read(stickerBackendProvider).install(packId);
      await ref.read(stickerCacheProvider).writeInstalled(user, state.value!);
    } catch (error) {
      AppLog.add('Пак $packId не установился: $error');
      state = AsyncData(before);
      rethrow;
    }
  }

  Future<void> uninstall(String packId) async {
    final user = _user;
    if (user == null) throw StateError('Нужно войти в аккаунт');
    final before = state.value ?? const <String>[];
    if (!before.contains(packId)) return;
    state = AsyncData([...before]..remove(packId));
    try {
      await ref.read(stickerBackendProvider).uninstall(packId);
      await ref.read(stickerCacheProvider).writeInstalled(user, state.value!);
    } catch (error) {
      AppLog.add('Пак $packId не удалился: $error');
      state = AsyncData(before);
      rethrow;
    }
  }
}

final installedStickerPacksProvider = AsyncNotifierProvider<InstalledStickerPacks, List<String>>(
  InstalledStickerPacks.new,
  retry: _noRetry,
);

/// Установленные паки, которые есть в каталоге, — вкладки панели стикеров.
final myStickerPacksProvider = Provider<List<StickerPack>>((ref) {
  final catalog = ref.watch(visibleStickerCatalogProvider).value;
  final installed = ref.watch(installedStickerPacksProvider).value;
  if (catalog == null || installed == null) return const [];
  return [
    for (final id in installed)
      if (catalog.pack(id) case final pack? when pack.stickers.isNotEmpty) pack,
  ];
});
