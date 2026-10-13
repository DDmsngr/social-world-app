import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Сервер магазина стикеров (миграция 0078): каталог одним вызовом и
/// коллекция текущего пользователя. Права проверяет база (RLS): поставить
/// можно только себе и только опубликованный пак.
abstract class StickerBackend {
  /// Сырой каталог: `{families, packs: [{…, stickers: […]}]}`.
  Future<Map<String, dynamic>> catalog();

  /// Id установленных паков в порядке вкладок панели.
  Future<List<String>> installed();

  /// Повторная установка ничего не меняет (on conflict do nothing).
  Future<void> install(String packId);

  Future<void> uninstall(String packId);
}

class SupabaseStickerBackend implements StickerBackend {
  SupabaseStickerBackend(this._client);

  final SupabaseClient _client;

  String get _me {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw StateError('Нужно войти в аккаунт');
    return id;
  }

  @override
  Future<Map<String, dynamic>> catalog() async =>
      Map<String, dynamic>.from(await _client.rpc('sticker_catalog') as Map);

  @override
  Future<List<String>> installed() async {
    final rows = await _client
        .from('user_sticker_packs')
        .select('pack_id, position, installed_at')
        .eq('profile_id', _me)
        .order('position', nullsFirst: false)
        .order('installed_at');
    return [for (final row in rows) row['pack_id'] as String];
  }

  @override
  Future<void> install(String packId) => _client
      .from('user_sticker_packs')
      .upsert(
        {'profile_id': _me, 'pack_id': packId},
        onConflict: 'profile_id,pack_id',
        ignoreDuplicates: true,
      );

  @override
  Future<void> uninstall(String packId) => _client
      .from('user_sticker_packs')
      .delete()
      .eq('profile_id', _me)
      .eq('pack_id', packId);
}

/// Последний каталог и коллекция на телефоне: панель стикеров открывается
/// сразу и без сети, а сервер догоняет в фоне.
class StickerCache {
  static const _catalogKey = 'stickers.catalog.v1';
  static String _installedKey(String userId) => 'stickers.installed.v1.$userId';

  Future<Map<String, dynamic>?> readCatalog() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_catalogKey);
      return raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> writeCatalog(Map<String, dynamic> json) async {
    try {
      await (await SharedPreferences.getInstance()).setString(_catalogKey, jsonEncode(json));
    } catch (_) {}
  }

  Future<List<String>?> readInstalled(String userId) async {
    try {
      return (await SharedPreferences.getInstance()).getStringList(_installedKey(userId));
    } catch (_) {
      return null;
    }
  }

  Future<void> writeInstalled(String userId, List<String> ids) async {
    try {
      await (await SharedPreferences.getInstance()).setStringList(_installedKey(userId), ids);
    } catch (_) {}
  }
}
