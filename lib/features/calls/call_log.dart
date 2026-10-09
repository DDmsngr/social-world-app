import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/env.dart';
import 'call_models.dart';

/// Звонок в ленте переписки: строка таблицы `calls`, показанная между
/// сообщениями по времени (как в Telegram).
class CallLogEntry {
  const CallLogEntry({
    required this.id,
    required this.callerId,
    required this.video,
    required this.status,
    required this.createdAt,
    this.answeredAt,
    this.endedAt,
  });

  factory CallLogEntry.fromRow(Map<String, dynamic> row) => CallLogEntry(
    id: row['id'] as String,
    callerId: row['caller_id'] as String,
    video: row['video'] as bool? ?? false,
    status: row['status'] as String,
    createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
    answeredAt: _date(row['answered_at']),
    endedAt: _date(row['ended_at']),
  );

  static DateTime? _date(Object? value) => value == null ? null : DateTime.parse(value as String).toLocal();

  final String id;
  final String callerId;
  final bool video;

  /// ringing / active / ended / declined / cancelled / missed / busy.
  final String status;
  final DateTime createdAt;
  final DateTime? answeredAt;
  final DateTime? endedAt;

  /// Состоялся ли разговор — от этого зависит цвет значка (красный —
  /// пропущенный или несостоявшийся).
  bool get talked => answeredAt != null;
}

String callLogTitle(CallLogEntry call, {required bool mine}) {
  final kind = call.video ? 'видеозвонок' : 'звонок';
  return mine ? 'Исходящий $kind' : 'Входящий $kind';
}

String callLogStatus(CallLogEntry call, {required bool mine}) {
  if (call.answeredAt != null && call.endedAt != null) {
    return formatCallDuration(call.endedAt!.difference(call.answeredAt!));
  }
  return switch (call.status) {
    'ringing' => 'Вызов…',
    'active' => 'Идёт разговор',
    'busy' => 'Занято',
    'declined' => mine ? 'Отклонён' : 'Вы отклонили',
    'missed' => mine ? 'Без ответа' : 'Пропущенный',
    'cancelled' => mine ? 'Отменён' : 'Пропущенный',
    _ => mine ? 'Не состоялся' : 'Пропущенный',
  };
}

/// Звонки переписки, живые: новый звонок и смена статуса приезжают сами
/// (таблица `calls` в публикации Realtime, RLS — только участникам).
final chatCallsProvider = StreamProvider.autoDispose.family<List<CallLogEntry>, String>((ref, conversationId) {
  if (!Env.isConfigured) return Stream.value(const []);
  return Supabase.instance.client
      .from('calls')
      .stream(primaryKey: ['id'])
      .eq('conversation_id', conversationId)
      .order('created_at', ascending: false)
      .limit(200)
      .map((rows) => [for (final row in rows) CallLogEntry.fromRow(row)]);
});
