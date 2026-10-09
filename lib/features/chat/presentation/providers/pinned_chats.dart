import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/conversation.dart';

/// Закреплённые чаты и каналы — наверху списка, в порядке закрепления
/// (последний закреплённый — выше). Хранятся на телефоне.
class PinnedChats extends Notifier<List<String>> {
  static const _key = 'chats.pinned';

  @override
  List<String> build() {
    ref.keepAlive();
    _load();
    return const [];
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getStringList(_key) ?? const [];
  }

  Future<void> toggle(String conversationId) async {
    final next = [...state];
    if (!next.remove(conversationId)) next.insert(0, conversationId);
    state = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, next);
  }
}

final pinnedChatsProvider = NotifierProvider<PinnedChats, List<String>>(PinnedChats.new);

/// Порядок списка: закреплённые сверху (в порядке закрепления), остальные —
/// где свежее последнее сообщение или пост, тот и выше.
List<Conversation> sortChats(List<Conversation> items, List<String> pinned) {
  final pinRank = {for (var i = 0; i < pinned.length; i++) pinned[i]: i};
  final epoch = DateTime.fromMillisecondsSinceEpoch(0);
  return [...items]..sort((a, b) {
    final pa = pinRank[a.id];
    final pb = pinRank[b.id];
    if (pa != null || pb != null) {
      if (pa == null) return 1;
      if (pb == null) return -1;
      return pa.compareTo(pb);
    }
    final ta = a.lastMessage?.sentAt ?? epoch;
    final tb = b.lastMessage?.sentAt ?? epoch;
    return tb.compareTo(ta);
  });
}
