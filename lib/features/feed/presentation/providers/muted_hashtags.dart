import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/env.dart';
import '../../../../core/debug/app_log.dart';
import '../../../../core/text/hashtags.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../domain/entities/post.dart';

const _prefsKey = 'muted_hashtags';

/// Чей список уже сверен с сервером: с этого момента сервер главный.
const _syncedKey = 'muted_hashtags_synced_for';

/// Скрытые теги, прочитанные в main() до первого кадра: иначе лента успела бы
/// показать посты, которые человек просил не показывать.
final initialMutedHashtagsProvider = Provider<Set<String>>((_) => const {});

Future<Set<String>> loadMutedHashtags() async {
  final prefs = await SharedPreferences.getInstance();
  return {...?prefs.getStringList(_prefsKey)};
}

/// Игнор-лист тегов: посты с такими тегами не показываются в ленте. Лента
/// самого тега открывается как раньше: туда человек пришёл сам.
///
/// Список хранится в аккаунте (0097) и переезжает на другой телефон; копия на
/// телефоне нужна, чтобы лента сразу пришла без скрытого, не дожидаясь сети.
/// При первой сверке на этом телефоне то, что скрыли до 0097, уходит на
/// сервер; дальше главный сервер, иначе тег, возвращённый на другом
/// телефоне, снова скрылся бы отсюда.
class MutedHashtagsController extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    ref.keepAlive();
    final userId = ref.watch(currentUserProvider)?.id;
    if (Env.isConfigured && userId != null) {
      Future.microtask(() => _sync(userId));
    }
    return stateOrNull ?? ref.read(initialMutedHashtagsProvider);
  }

  SupabaseClient get _client => Supabase.instance.client;

  Future<void> _sync(String userId) async {
    try {
      final rows =
          await _client.from('muted_hashtags').select('tag') as List<dynamic>;
      final server = {
        for (final row in rows) (row as Map<String, dynamic>)['tag'] as String,
      };
      final prefs = await SharedPreferences.getInstance();
      final synced = prefs.getString(_syncedKey);
      if (synced != userId) {
        // Перенести можно только «ничейный» список, скрытый до 0097. Если
        // телефон уже сверялся под другим аккаунтом, его теги не наши.
        final onlyHere = synced == null
            ? state.difference(server)
            : const <String>{};
        if (onlyHere.isNotEmpty) {
          await _client.from('muted_hashtags').upsert([
            for (final tag in onlyHere) {'tag': tag},
          ], ignoreDuplicates: true);
          server.addAll(onlyHere);
        }
        await prefs.setString(_syncedKey, userId);
      }
      await _save(server);
    } catch (error) {
      AppLog.add('Скрытые теги не сверились: $error');
    }
  }

  Future<void> _save(Set<String> tags) async {
    state = tags;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, tags.toList()..sort());
  }

  bool isMuted(String tag) => state.contains(normalizeHashtag(tag));

  Future<void> toggle(String tag) async {
    final t = normalizeHashtag(tag);
    if (t.isEmpty) return;
    final mute = !state.contains(t);
    await _save(mute ? {...state, t} : ({...state}..remove(t)));
    if (!Env.isConfigured || ref.read(currentUserProvider) == null) return;
    try {
      if (mute) {
        await _client.from('muted_hashtags').upsert({
          'tag': t,
        }, ignoreDuplicates: true);
      } else {
        await _client.from('muted_hashtags').delete().eq('tag', t);
      }
    } catch (error) {
      AppLog.add('Скрытый тег не сохранился в аккаунте: $error');
    }
  }
}

final mutedHashtagsProvider =
    NotifierProvider<MutedHashtagsController, Set<String>>(
      MutedHashtagsController.new,
    );

/// Есть ли в посте скрытый тег.
bool hasMutedHashtag(Post post, Set<String> muted) {
  if (muted.isEmpty) return false;
  return extractHashtags(
    '${post.title ?? ''} ${post.body ?? ''}',
  ).any(muted.contains);
}
