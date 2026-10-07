import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/env.dart';
import '../../../../core/debug/app_log.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../domain/entities/conversation.dart';

/// Личные настройки чата (миграция 0057): архив, «удалён у меня», звук, фон.
class ChatSettings {
  const ChatSettings({this.archivedAt, this.clearedAt, this.sound, this.wallpaper});

  final DateTime? archivedAt;
  final DateTime? clearedAt;
  final String? sound;
  final String? wallpaper;

  static const none = ChatSettings();
}

/// Чат убран из основного списка: архивирован или «удалён у меня» — и после
/// этого в нём не было нового сообщения. Новое сообщение возвращает чат в
/// список само.
bool hiddenFromList(Conversation c, ChatSettings s) {
  final last = c.lastMessage?.sentAt;
  bool before(DateTime? mark) => mark != null && (last == null || !last.isAfter(mark));
  return before(s.clearedAt) || before(s.archivedAt);
}

/// В архиве и не «удалён»: то, что показывает экран «Архив».
bool inArchive(Conversation c, ChatSettings s) {
  final last = c.lastMessage?.sentAt;
  final cleared = s.clearedAt != null && (last == null || !last.isAfter(s.clearedAt!));
  final archived = s.archivedAt != null && (last == null || !last.isAfter(s.archivedAt!));
  return archived && !cleared;
}

final chatSettingsProvider = FutureProvider<Map<String, ChatSettings>>((ref) async {
  ref.keepAlive();
  if (!Env.isConfigured || ref.watch(currentUserProvider) == null) return const {};
  final rows = await Supabase.instance.client.rpc('my_chat_settings');
  DateTime? time(Object? raw) => raw == null ? null : DateTime.parse(raw as String).toLocal();
  return {
    for (final row in (rows as List).cast<Map<String, dynamic>>())
      row['conversation_id'] as String: ChatSettings(
        archivedAt: time(row['archived_at']),
        clearedAt: time(row['cleared_at']),
        sound: row['sound'] as String?,
        wallpaper: row['wallpaper'] as String?,
      ),
  };
});

/// Настройки одного чата; без записи — обычные.
ChatSettings chatSettingsOf(WidgetRef ref, String conversationId) =>
    ref.watch(chatSettingsProvider).asData?.value[conversationId] ?? ChatSettings.none;

Future<void> setChatArchived(WidgetRef ref, String conversationId, bool archived) async {
  await Supabase.instance.client.rpc(
    'set_chat_archived',
    params: {'p_conversation': conversationId, 'p_archived': archived},
  );
  ref.invalidate(chatSettingsProvider);
}

/// «Удалить чат у себя»: история скрывается, у собеседника всё остаётся.
Future<void> clearChatForMe(WidgetRef ref, String conversationId) async {
  await Supabase.instance.client.rpc('clear_chat_for_me', params: {'p_conversation': conversationId});
  ref.invalidate(chatSettingsProvider);
}

/// Звук и фон одним вызовом: сервер хранит оба поля вместе, поэтому второе
/// берём из текущих настроек.
Future<void> saveChatLook(
  WidgetRef ref,
  String conversationId, {
  required String? sound,
  required String? wallpaper,
}) async {
  await Supabase.instance.client.rpc(
    'set_chat_look',
    params: {'p_conversation': conversationId, 'p_sound': sound, 'p_wallpaper': wallpaper},
  );
  ref.invalidate(chatSettingsProvider);
}

/// Свой фон сразу, собеседнику — предложение (личные чаты).
Future<void> offerChatWallpaper(WidgetRef ref, String conversationId, String wallpaper) async {
  await Supabase.instance.client.rpc(
    'offer_chat_wallpaper',
    params: {'p_conversation': conversationId, 'p_wallpaper': wallpaper},
  );
  ref.invalidate(chatSettingsProvider);
}

class WallpaperOffer {
  const WallpaperOffer({required this.id, required this.fromId, required this.wallpaper});

  final String id;
  final String fromId;
  final String wallpaper;
}

/// Неотвеченное предложение фона мне в этом чате. Обновляется на лету: у
/// собеседника оно появляется, как только его отправили.
final wallpaperOfferProvider = StreamProvider.autoDispose.family<WallpaperOffer?, String>((
  ref,
  conversationId,
) {
  if (!Env.isConfigured) return const Stream.empty();
  final me = ref.watch(currentUserProvider)?.id;
  if (me == null) return const Stream.empty();
  final client = Supabase.instance.client;
  final controller = StreamController<WallpaperOffer?>();
  Timer? debounce;

  Future<void> load() async {
    try {
      final rows = await client
          .from('chat_wallpaper_offers')
          .select('id, from_id, wallpaper')
          .eq('conversation_id', conversationId)
          .eq('to_id', me)
          .eq('status', 'pending')
          .order('created_at', ascending: false)
          .limit(1);
      if (controller.isClosed) return;
      controller.add(
        rows.isEmpty
            ? null
            : WallpaperOffer(
                id: rows.first['id'] as String,
                fromId: rows.first['from_id'] as String,
                wallpaper: rows.first['wallpaper'] as String,
              ),
      );
    } catch (error) {
      AppLog.add('Предложение фона не загрузилось: $error');
    }
  }

  final channel = client
      .channel('wallpaper:$conversationId')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'chat_wallpaper_offers',
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

Future<void> respondWallpaperOffer(WidgetRef ref, String offerId, {required bool accept}) async {
  await Supabase.instance.client.rpc(
    'respond_chat_wallpaper',
    params: {'p_offer': offerId, 'p_accept': accept},
  );
  ref.invalidate(chatSettingsProvider);
}
