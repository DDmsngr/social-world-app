import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/env.dart';

/// Как чат беспокоит. Решение принимает сервер (push-send), здесь только то,
/// что человек выбрал, и значок в списке.
enum NotifyMode {
  sound('sound'),
  vibrate('vibrate'),
  silent('silent'),
  off('off');

  const NotifyMode(this.wire);
  final String wire;

  static NotifyMode parse(Object? raw) => NotifyMode.values.firstWhere(
    (m) => m.wire == raw,
    orElse: () => NotifyMode.sound,
  );
}

class ChatNotify {
  const ChatNotify({this.mode = NotifyMode.sound, this.mutedUntil});

  final NotifyMode mode;
  final DateTime? mutedUntil;

  static const normal = ChatNotify();

  bool get timerActive => mutedUntil != null && mutedUntil!.isAfter(DateTime.now());

  /// Чат сейчас молчит совсем: выключен или идёт таймер.
  bool get isMuted => mode == NotifyMode.off || timerActive;

  /// Режим, отличный от обычного (для значка в списке).
  bool get isCustom => isMuted || mode != NotifyMode.sound;
}

final chatNotifyProvider = FutureProvider<Map<String, ChatNotify>>((ref) async {
  ref.keepAlive();
  if (!Env.isConfigured) return const {};
  final rows = await Supabase.instance.client.rpc('my_chat_notifications');
  return {
    for (final row in (rows as List).cast<Map<String, dynamic>>())
      row['conversation_id'] as String: ChatNotify(
        mode: NotifyMode.parse(row['mode']),
        mutedUntil: row['muted_until'] == null
            ? null
            : DateTime.parse(row['muted_until'] as String).toLocal(),
      ),
  };
});

/// Настройки одного чата; без записи — обычные.
ChatNotify chatNotifyOf(WidgetRef ref, String conversationId) =>
    ref.watch(chatNotifyProvider).asData?.value[conversationId] ??
    ChatNotify.normal;

Future<void> saveChatNotify(
  WidgetRef ref,
  String conversationId,
  ChatNotify value,
) async {
  await Supabase.instance.client.rpc(
    'set_chat_notification',
    params: {
      'p_conversation': conversationId,
      'p_mode': value.mode.wire,
      'p_muted_until': value.mutedUntil?.toUtc().toIso8601String(),
    },
  );
  ref.invalidate(chatNotifyProvider);
}
