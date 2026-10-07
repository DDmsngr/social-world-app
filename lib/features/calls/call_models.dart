/// Звонок в личном чате (миграция 0058). Сервер знает только факт звонка и его
/// состояние, звук и видео идут напрямую между телефонами по WebRTC.
class CallInfo {
  const CallInfo({
    required this.id,
    required this.conversationId,
    required this.peerId,
    required this.peerName,
    this.peerAvatarUrl,
    this.video = false,
    required this.outgoing,
  });

  final String id;
  final String conversationId;
  final String peerId;
  final String peerName;
  final String? peerAvatarUrl;
  final bool video;

  /// Звоню я — или звонят мне.
  final bool outgoing;

  /// Из data-пуша (push-send, тип `call`) или из `extra` звонилки — там те же
  /// ключи. null, если пуш не про звонок или в нём чего-то не хватает.
  static CallInfo? fromPush(Map<String, dynamic> data) {
    final id = data['call_id'];
    final conversation = data['conversation_id'];
    final caller = data['caller_id'];
    if (id is! String || conversation is! String || caller is! String) return null;
    final avatar = data['caller_avatar'];
    return CallInfo(
      id: id,
      conversationId: conversation,
      peerId: caller,
      peerName: (data['caller_name'] as String?)?.trim().isNotEmpty == true
          ? data['caller_name'] as String
          : 'ChaWo',
      peerAvatarUrl: avatar is String && avatar.isNotEmpty ? avatar : null,
      video: data['video'] == '1' || data['video'] == true,
      outgoing: false,
    );
  }

  Map<String, dynamic> toPush() => {
    'call_id': id,
    'conversation_id': conversationId,
    'caller_id': peerId,
    'caller_name': peerName,
    'caller_avatar': peerAvatarUrl ?? '',
    'video': video ? '1' : '0',
  };
}

/// Что сейчас со звонком на этом телефоне.
enum CallPhase {
  /// Звонков нет.
  idle,

  /// Исходящий: у собеседника звонит.
  dialing,

  /// Ответили, телефоны договариваются о связи.
  connecting,

  /// Идёт разговор.
  active,

  /// Связь пропала, пробуем вернуть.
  reconnecting,

  /// Звонок кончился, экран вот-вот закроется.
  ended,
}

/// Почему звонок кончился — для подписи на экране.
enum CallEndReason {
  hangUp('Звонок завершён'),
  busy('Занято'),
  noAnswer('Не отвечает'),
  declined('Звонок отклонён'),
  cancelled('Звонок отменён'),
  failed('Не удалось соединиться'),
  noMicrophone('Нет доступа к микрофону'),
  unavailable('Звонок недоступен');

  const CallEndReason(this.label);

  final String label;

  /// Итог звонка с сервера (calls.status) глазами этого телефона.
  static CallEndReason fromStatus(String? status, {required bool outgoing}) => switch (status) {
    'busy' => CallEndReason.busy,
    'missed' => outgoing ? CallEndReason.noAnswer : CallEndReason.cancelled,
    'declined' => outgoing ? CallEndReason.declined : CallEndReason.hangUp,
    'cancelled' => CallEndReason.cancelled,
    _ => CallEndReason.hangUp,
  };
}

/// Подпись под именем на экране звонка.
String callPhaseLabel(CallPhase phase, {required bool video, Duration? talked, CallEndReason? reason}) =>
    switch (phase) {
      CallPhase.idle => '',
      CallPhase.dialing => video ? 'Видеозвонок…' : 'Вызов…',
      CallPhase.connecting => 'Соединение…',
      CallPhase.active => formatCallDuration(talked ?? Duration.zero),
      CallPhase.reconnecting => 'Восстанавливаем связь…',
      CallPhase.ended => reason?.label ?? CallEndReason.hangUp.label,
    };

/// 0:07, 12:30, 1:02:03.
String formatCallDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}

/// Сигналы WebRTC через Realtime broadcast по каналу `call:<id>`.
/// ready — получатель на месте и ждёт offer; offer/answer — описание сессии;
/// ice — кандидат пути; bye — положили трубку; cam — включил/выключил камеру.
abstract final class CallSignal {
  static const ready = 'ready';
  static const offer = 'offer';
  static const answer = 'answer';
  static const ice = 'ice';
  static const bye = 'bye';
  static const cam = 'cam';
}
