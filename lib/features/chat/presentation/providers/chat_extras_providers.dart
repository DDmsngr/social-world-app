import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/env.dart';
import '../../../../core/debug/app_log.dart';

/// «В сети / был(а) …» собеседника личного чата (миграция 0041).
class PeerPresence {
  const PeerPresence({required this.online, this.lastSeen});

  final bool online;
  final DateTime? lastSeen;

  /// Подпись под именем в шапке; null — показывать нечего.
  String? label(DateTime now) {
    if (online) return 'в сети';
    final seen = lastSeen;
    if (seen == null) return null;
    final hh = seen.hour.toString().padLeft(2, '0');
    final mm = seen.minute.toString().padLeft(2, '0');
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(seen.year, seen.month, seen.day);
    final diff = today.difference(day).inDays;
    if (now.difference(seen).inMinutes < 60) {
      final m = now.difference(seen).inMinutes.clamp(1, 59);
      return 'был(а) $m мин назад';
    }
    if (diff == 0) return 'был(а) сегодня в $hh:$mm';
    if (diff == 1) return 'был(а) вчера в $hh:$mm';
    const months = [
      'янв', 'фев', 'мар', 'апр', 'мая', 'июн',
      'июл', 'авг', 'сен', 'окт', 'ноя', 'дек',
    ];
    return 'был(а) ${seen.day} ${months[seen.month - 1]}';
  }
}

/// Раз в 20 секунд, пока шапка на экране (раньше раз в минуту — статус
/// заметно отставал).
final peerPresenceProvider = StreamProvider.autoDispose
    .family<PeerPresence?, String>((ref, conversationId) async* {
      if (!Env.isConfigured) {
        yield null;
        return;
      }
      final client = Supabase.instance.client;
      while (true) {
        try {
          final rows = await client.rpc(
            'chat_peer_presence',
            params: {'in_conversation': conversationId},
          ) as List;
          if (rows.isEmpty) {
            yield null;
          } else {
            final row = rows.first as Map<String, dynamic>;
            yield PeerPresence(
              online: row['online'] as bool? ?? false,
              lastSeen: row['last_seen'] == null
                  ? null
                  : DateTime.parse(row['last_seen'] as String).toLocal(),
            );
          }
        } catch (error) {
          AppLog.add('Присутствие собеседника: $error');
        }
        await Future<void>.delayed(const Duration(seconds: 20));
      }
    });

/// Реакция на сообщение: эмодзи, сколько людей, есть ли среди них я.
class ReactionCount {
  const ReactionCount({required this.emoji, required this.count, required this.mine});

  final String emoji;
  final int count;
  final bool mine;
}

typedef ChatReactions = Map<String, List<ReactionCount>>;

/// Реакции чата: сводка с сервера + реалтайм на изменения (кто-то поставил
/// или снял) — тогда сводка перечитывается целиком, она маленькая.
final chatReactionsProvider = StreamProvider.autoDispose
    .family<ChatReactions, String>((ref, conversationId) {
      if (!Env.isConfigured) return Stream.value(const {});
      final client = Supabase.instance.client;
      final controller = StreamController<ChatReactions>();
      Timer? debounce;

      Future<void> load() async {
        try {
          final rows = await client.rpc(
            'chat_reactions',
            params: {'in_conversation': conversationId},
          ) as List;
          final result = <String, List<ReactionCount>>{};
          for (final raw in rows.cast<Map<String, dynamic>>()) {
            result.putIfAbsent(raw['message_id'] as String, () => []).add(
              ReactionCount(
                emoji: raw['emoji'] as String,
                count: (raw['count'] as num).toInt(),
                mine: raw['mine'] as bool? ?? false,
              ),
            );
          }
          if (!controller.isClosed) controller.add(result);
        } catch (error) {
          AppLog.add('Реакции не загрузились: $error');
        }
      }

      final channel = client
          .channel('reactions:$conversationId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'chat_message_reactions',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'conversation_id',
              value: conversationId,
            ),
            callback: (_) {
              debounce?.cancel();
              debounce = Timer(const Duration(milliseconds: 250), load);
            },
          )
          .subscribe();

      unawaited(load());
      ref.onDispose(() {
        debounce?.cancel();
        unawaited(client.removeChannel(channel));
        controller.close();
      });
      return controller.stream;
    });

Future<void> toggleReaction(
  WidgetRef ref,
  String conversationId,
  String messageId,
  String emoji,
) async {
  // Лёгкий отклик сразу при нажатии, не дожидаясь сети.
  unawaited(HapticFeedback.lightImpact());
  await Supabase.instance.client.rpc(
    'toggle_chat_reaction',
    params: {'in_message': messageId, 'in_emoji': emoji},
  );
  // Свою реакцию показываем сразу, не дожидаясь реалтайма. Пока сводка
  // перечитывается, на экране остаётся прежняя.
  ref.invalidate(chatReactionsProvider(conversationId));
}

/// Реакции по умолчанию: первые шесть — быстрая полоса, все вместе — окно «⋯».
const popularReactions = [
  '❤️', '👍', '😂', '😮', '😢', '🔥', '👎', '🙏', '👏', '🥰',
  '😍', '🤔', '🤯', '😱', '😡', '🎉', '🤩', '🤮', '💩', '🤝',
  '😎', '😁', '😭', '🥳', '😴', '💔', '💯', '👀', '🙌', '✨',
  '😉', '🤗', '😅', '🤣', '👌',
];

/// Частота, с которой человек ставит реакции: от неё зависит порядок в панели.
/// Хранится на устройстве, чтение синхронное после [load].
class ReactionUsage {
  ReactionUsage._();
  static const _key = 'reaction_usage';
  static final Map<String, int> _counts = {};
  static bool _loaded = false;

  static Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final line in prefs.getStringList(_key) ?? const <String>[]) {
        final i = line.lastIndexOf('|');
        final n = i < 0 ? null : int.tryParse(line.substring(i + 1));
        if (n != null) _counts[line.substring(0, i)] = n;
      }
    } catch (_) {}
    _loaded = true;
  }

  static Future<void> record(String emoji) async {
    _counts[emoji] = (_counts[emoji] ?? 0) + 1;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_key, [for (final e in _counts.entries) '${e.key}|${e.value}']);
    } catch (_) {}
  }

  /// Все популярные плюс те, что человек ставил сам, по убыванию частоты;
  /// при равенстве — в исходном порядке.
  static List<String> ranked() {
    final all = [
      ...popularReactions,
      for (final e in _counts.keys) if (!popularReactions.contains(e)) e,
    ];
    final order = {for (var i = 0; i < all.length; i++) all[i]: i};
    all.sort((a, b) {
      final c = (_counts[b] ?? 0).compareTo(_counts[a] ?? 0);
      return c != 0 ? c : order[a]!.compareTo(order[b]!);
    });
    return all;
  }

  static List<String> quick() => ranked().take(6).toList();
  static List<String> extended() => ranked().take(35).toList();
}

/// Быстрые реакции в меню сообщения (по умолчанию, пока нет статистики).
const quickReactions = ['❤️', '👍', '😂', '😮', '😢', '🔥'];
