import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/env.dart';
import '../../core/debug/app_log.dart';
import '../../core/links/deep_links.dart';
import '../auth/presentation/providers/auth_providers.dart';

/// Что можно сохранить. Совпадает со значениями `saved_items.target_type`.
enum SavedKind {
  post('Публикация', LinkTarget.post),
  event('Событие', LinkTarget.event),
  place('Место', LinkTarget.place),
  route('Маршрут', LinkTarget.route);

  const SavedKind(this.label, this.link);

  final String label;
  final LinkTarget link;

  static SavedKind? parse(dynamic raw) {
    for (final kind in values) {
      if (kind.name == raw) return kind;
    }
    return null;
  }
}

class SavedItem {
  const SavedItem({
    required this.kind,
    required this.id,
    required this.title,
    required this.savedAt,
    this.subtitle,
  });

  final SavedKind kind;
  final String id;
  final String title;
  final String? subtitle;
  final DateTime savedAt;

  String get key => savedKey(kind, id);
}

String savedKey(SavedKind kind, String id) => '${kind.name}:$id';

abstract interface class SavedRepository {
  Future<Set<String>> loadKeys();

  Future<List<SavedItem>> loadItems();

  /// [title]/[subtitle] нужны только заглушке: сервер собирает названия сам.
  Future<void> setSaved(
    SavedKind kind,
    String id, {
    required bool saved,
    String? title,
    String? subtitle,
  });
}

class SupabaseSavedRepository implements SavedRepository {
  SupabaseSavedRepository(this._client);

  final SupabaseClient _client;

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw const AuthException('Нет активной сессии');
    return id;
  }

  @override
  Future<Set<String>> loadKeys() async {
    final rows = await _client
        .from('saved_items')
        .select('target_type,target_id')
        .eq('profile_id', _userId);
    return {
      for (final row in rows)
        if (SavedKind.parse(row['target_type']) case final kind?)
          savedKey(kind, row['target_id'] as String),
    };
  }

  @override
  Future<List<SavedItem>> loadItems() async {
    final rows = await _client.rpc('my_saved') as List<dynamic>;
    return [
      for (final raw in rows)
        if (SavedKind.parse((raw as Map<String, dynamic>)['target_type'])
            case final kind?)
          SavedItem(
            kind: kind,
            id: raw['target_id'] as String,
            title: (raw['title'] as String?) ?? kind.label,
            subtitle: raw['subtitle'] as String?,
            savedAt: DateTime.parse(raw['saved_at'] as String),
          ),
    ];
  }

  @override
  Future<void> setSaved(
    SavedKind kind,
    String id, {
    required bool saved,
    String? title,
    String? subtitle,
  }) async {
    if (saved) {
      await _client.from('saved_items').upsert({
        'profile_id': _userId,
        'target_type': kind.name,
        'target_id': id,
      }, onConflict: 'profile_id,target_type,target_id');
    } else {
      await _client.from('saved_items').delete().match({
        'profile_id': _userId,
        'target_type': kind.name,
        'target_id': id,
      });
    }
  }
}

class LocalSavedRepository implements SavedRepository {
  final _items = <String, SavedItem>{};

  @override
  Future<Set<String>> loadKeys() async => _items.keys.toSet();

  @override
  Future<List<SavedItem>> loadItems() async =>
      _items.values.toList()..sort((a, b) => b.savedAt.compareTo(a.savedAt));

  @override
  Future<void> setSaved(
    SavedKind kind,
    String id, {
    required bool saved,
    String? title,
    String? subtitle,
  }) async {
    final key = savedKey(kind, id);
    if (!saved) {
      _items.remove(key);
      return;
    }
    _items[key] = SavedItem(
      kind: kind,
      id: id,
      title: title ?? kind.label,
      subtitle: subtitle,
      savedAt: DateTime.now(),
    );
  }
}

final savedRepositoryProvider = Provider<SavedRepository>((ref) {
  ref.keepAlive();
  if (!Env.isConfigured) return LocalSavedRepository();
  return SupabaseSavedRepository(Supabase.instance.client);
});

/// Ключи сохранённого — по ним карточки знают, залита ли закладка. Меняется
/// сразу, с откатом при сбое.
class SavedController extends AsyncNotifier<Set<String>> {
  @override
  Future<Set<String>> build() async {
    ref.keepAlive();
    if (ref.watch(currentUserProvider) == null) return const {};
    try {
      return await ref.watch(savedRepositoryProvider).loadKeys();
    } catch (error) {
      AppLog.add('Сохранённое не загрузилось: $error');
      return const {};
    }
  }

  bool isSaved(SavedKind kind, String id) =>
      state.value?.contains(savedKey(kind, id)) ?? false;

  /// Возвращает новое состояние закладки или `null`, если сохранить не вышло.
  Future<bool?> toggle(
    SavedKind kind,
    String id, {
    String? title,
    String? subtitle,
  }) async {
    final key = savedKey(kind, id);
    final before = state.value ?? const <String>{};
    final want = !before.contains(key);

    state = AsyncData(want ? {...before, key} : ({...before}..remove(key)));
    try {
      await ref
          .read(savedRepositoryProvider)
          .setSaved(kind, id, saved: want, title: title, subtitle: subtitle);
      ref.invalidate(savedItemsProvider);
      return want;
    } catch (error) {
      AppLog.add('Закладка не сохранилась: $error');
      state = AsyncData(before);
      return null;
    }
  }
}

final savedProvider = AsyncNotifierProvider<SavedController, Set<String>>(
  SavedController.new,
);

final savedItemsProvider = FutureProvider.autoDispose<List<SavedItem>>((ref) {
  return ref.watch(savedRepositoryProvider).loadItems();
});
