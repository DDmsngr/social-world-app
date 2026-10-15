import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/text/hashtags.dart';
import '../../domain/entities/post.dart';

const _prefsKey = 'muted_hashtags';

/// Скрытые теги, прочитанные в main() до первого кадра: иначе лента успела бы
/// показать посты, которые человек просил не показывать.
final initialMutedHashtagsProvider = Provider<Set<String>>((_) => const {});

Future<Set<String>> loadMutedHashtags() async {
  final prefs = await SharedPreferences.getInstance();
  return {...?prefs.getStringList(_prefsKey)};
}

/// Игнор-лист тегов: посты с такими тегами не показываются в ленте. Живёт на
/// телефоне. Лента самого тега открывается как раньше: туда человек пришёл сам.
class MutedHashtagsController extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    ref.keepAlive();
    return ref.read(initialMutedHashtagsProvider);
  }

  bool isMuted(String tag) => state.contains(normalizeHashtag(tag));

  Future<void> toggle(String tag) async {
    final t = normalizeHashtag(tag);
    if (t.isEmpty) return;
    state = state.contains(t) ? ({...state}..remove(t)) : {...state, t};
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, state.toList()..sort());
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
