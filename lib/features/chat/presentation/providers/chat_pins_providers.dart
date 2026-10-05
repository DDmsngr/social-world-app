import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/env.dart';
import '../../../../core/debug/app_log.dart';
import '../../domain/entities/chat_message.dart';
import 'chat_providers.dart';

/// Закреплённое сообщение: только id и когда закреплено. Текст на сервере
/// не лежит (в личных диалогах он зашифрован) — его достаёт клиент.
class ChatPin {
  const ChatPin({required this.messageId, required this.pinnedAt});

  final String messageId;
  final DateTime pinnedAt;
}

/// Закрепы чата, свежие первыми. Реалтайм: закрепил или открепил собеседник
/// или админ — список перечитывается.
final chatPinsProvider = StreamProvider.autoDispose
    .family<List<ChatPin>, String>((ref, conversationId) {
      if (!Env.isConfigured) return Stream.value(const []);
      final client = Supabase.instance.client;
      final controller = StreamController<List<ChatPin>>();
      Timer? debounce;

      Future<void> load() async {
        try {
          final rows = await client.rpc(
            'chat_pins_list',
            params: {'in_conversation': conversationId},
          ) as List;
          if (controller.isClosed) return;
          controller.add([
            for (final raw in rows.cast<Map<String, dynamic>>())
              ChatPin(
                messageId: raw['message_id'] as String,
                pinnedAt: DateTime.parse(raw['pinned_at'] as String).toLocal(),
              ),
          ]);
        } catch (error) {
          // Миграция 0045 может быть не накатана — закрепов просто нет.
          AppLog.add('Закрепы не загрузились: $error');
          if (!controller.isClosed) controller.add(const []);
        }
      }

      final channel = client
          .channel('pins:$conversationId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'chat_pins',
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

/// Закрепить или открепить. Права проверяет сервер: в личном чате любой из
/// двоих, в группе и канале — владелец и админы.
Future<void> setPinned(
  WidgetRef ref,
  String conversationId,
  String messageId, {
  required bool pinned,
}) async {
  await Supabase.instance.client.rpc(
    pinned ? 'pin_chat_message' : 'unpin_chat_message',
    params: {'in_message': messageId},
  );
  ref.invalidate(chatPinsProvider(conversationId));
}

/// Закреплённые сообщения уже расшифрованными, свежий закреп первым. Что есть
/// в загруженной ленте — берём оттуда, старое докачиваем отдельным запросом.
final pinnedMessagesProvider = FutureProvider.autoDispose
    .family<List<ChatMessage>, String>((ref, conversationId) async {
      final pins = ref.watch(chatPinsProvider(conversationId)).value ?? const [];
      if (pins.isEmpty) return const [];
      final loaded = ref.watch(messagesProvider(conversationId)).value ?? const [];
      final byId = {for (final m in loaded) m.id: m};
      final missing = [
        for (final pin in pins)
          if (!byId.containsKey(pin.messageId)) pin.messageId,
      ];
      if (missing.isNotEmpty) {
        try {
          final fetched = await ref
              .read(chatRepositoryProvider)
              .loadMessagesByIds(conversationId, missing);
          for (final m in fetched) {
            byId[m.id] = m;
          }
        } catch (error) {
          AppLog.add('Закреплённые сообщения не докачались: $error');
        }
      }
      return [
        for (final pin in pins)
          if (byId[pin.messageId] != null) byId[pin.messageId]!,
      ];
    });

// ── закладки ────────────────────────────────────────────────────────────────

class BookmarkRef {
  const BookmarkRef({
    required this.messageId,
    required this.conversationId,
    required this.createdAt,
  });

  final String messageId;
  final String conversationId;
  final DateTime createdAt;
}

/// Мои закладки на сообщения (все чаты), свежие первыми. Личные: другим не
/// видны. Хранятся только id — текст достаётся на месте.
class MyBookmarks extends AsyncNotifier<List<BookmarkRef>> {
  @override
  Future<List<BookmarkRef>> build() async {
    ref.keepAlive();
    if (!Env.isConfigured) return const [];
    try {
      final rows = await Supabase.instance.client.rpc('my_chat_bookmarks') as List;
      return [
        for (final raw in rows.cast<Map<String, dynamic>>())
          BookmarkRef(
            messageId: raw['message_id'] as String,
            conversationId: raw['conversation_id'] as String,
            createdAt: DateTime.parse(raw['created_at'] as String).toLocal(),
          ),
      ];
    } catch (error) {
      AppLog.add('Закладки не загрузились: $error');
      return const [];
    }
  }

  bool has(String messageId) =>
      state.value?.any((b) => b.messageId == messageId) ?? false;

  /// Поставить или снять. Сразу меняем список на экране, сервер подтверждает.
  Future<bool> toggle(String messageId, String conversationId) async {
    final before = state.value ?? const <BookmarkRef>[];
    final wasOn = has(messageId);
    state = AsyncData(
      wasOn
          ? [for (final b in before) if (b.messageId != messageId) b]
          : [
              BookmarkRef(
                messageId: messageId,
                conversationId: conversationId,
                createdAt: DateTime.now(),
              ),
              ...before,
            ],
    );
    try {
      final on = await Supabase.instance.client.rpc(
        'toggle_chat_bookmark',
        params: {'in_message': messageId},
      ) as bool;
      return on;
    } catch (error) {
      state = AsyncData(before);
      rethrow;
    }
  }
}

final myBookmarksProvider =
    AsyncNotifierProvider<MyBookmarks, List<BookmarkRef>>(MyBookmarks.new);

/// Сообщение под закладкой вместе с чатом, где оно лежит.
class BookmarkedMessage {
  const BookmarkedMessage({required this.message, required this.createdAt});

  final ChatMessage message;
  final DateTime createdAt;
}

/// Закладки с расшифрованным текстом. [conversationId] — только этого чата,
/// null — все. Чаты разбираем по одному: у каждого личного свои ключи.
final bookmarkedMessagesProvider = FutureProvider.autoDispose
    .family<List<BookmarkedMessage>, String?>((ref, conversationId) async {
      final refs = ref.watch(myBookmarksProvider).value ?? const [];
      final wanted = [
        for (final b in refs)
          if (conversationId == null || b.conversationId == conversationId) b,
      ];
      if (wanted.isEmpty) return const [];

      final byConversation = <String, List<BookmarkRef>>{};
      for (final b in wanted) {
        byConversation.putIfAbsent(b.conversationId, () => []).add(b);
      }
      final repository = ref.read(chatRepositoryProvider);
      final found = <String, ChatMessage>{};
      await Future.wait([
        for (final entry in byConversation.entries)
          () async {
            try {
              final list = await repository.loadMessagesByIds(
                entry.key,
                [for (final b in entry.value) b.messageId],
              );
              for (final m in list) {
                found[m.id] = m;
              }
            } catch (error) {
              AppLog.add('Закладки чата ${entry.key} не открылись: $error');
            }
          }(),
      ]);
      return [
        for (final b in wanted)
          if (found[b.messageId] != null)
            BookmarkedMessage(message: found[b.messageId]!, createdAt: b.createdAt),
      ];
    });
