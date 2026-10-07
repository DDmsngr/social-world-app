import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/env.dart';
import '../../../../core/debug/app_log.dart';
import '../../../auth/presentation/providers/auth_providers.dart';

/// Что показывать вместо скучного «печатает». Фразу выбирает тот, кто пишет,
/// в начале набора, и она держится, пока он не замолчит: у собеседника она не
/// мигает от нажатия к нажатию.
const typingPhrases = [
  'печатает…',
  'подбирает слова…',
  'думает…',
  'ищет нужную букву…',
  'сочиняет шедевр…',
  'стирает и пишет заново…',
  'собирается с мыслями…',
  'ищет смайлик получше…',
  'перечитывает написанное…',
  'советуется с подушкой…',
  'вспоминает, как пишется…',
  'формулирует тактично…',
];

/// Что человек отправляет вместо набора текста (MessageKind.wire).
const uploadPhrases = {
  'image': 'отправляет фото…',
  'video': 'отправляет видео…',
  'video_note': 'отправляет видеосообщение…',
  'voice': 'отправляет голосовое…',
  'file': 'отправляет файл…',
};

class TypingEntry {
  const TypingEntry({
    required this.profileId,
    required this.name,
    required this.phrase,
    required this.until,
    this.activity,
  });

  final String profileId;
  final String name;
  final int phrase;
  final DateTime until;

  /// null — печатает; иначе тип отправляемого вложения.
  final String? activity;

  String get phraseText => uploadPhrases[activity] ?? typingPhrases[phrase % typingPhrases.length];
}

/// Как показать, кто пишет: в личном чате — одна фраза, в группе — с именем.
String typingLabel(List<TypingEntry> entries, {required bool direct}) {
  if (entries.isEmpty) return '';
  if (direct) return entries.first.phraseText;
  if (entries.length == 1) return '${entries.first.name} ${entries.first.phraseText}';
  if (entries.length == 2) return '${entries[0].name} и ${entries[1].name} печатают…';
  return '${entries[0].name} и ещё ${entries.length - 1} печатают…';
}

/// Набор текста по каналу Realtime (broadcast): ничего не пишется в базу и не
/// хранится, событие живёт несколько секунд. В событии только имя и номер
/// фразы — ни текста, ни содержимого, так что шифрованию личных чатов это не
/// мешает.
class TypingHub {
  TypingHub(this._client, this._conversationId, this._myId, this._myName) {
    final channel = _client.channel('typing:$_conversationId');
    _channel = channel;
    channel
        .onBroadcast(event: 'typing', callback: _onEvent)
        .subscribe();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _prune());
  }

  static const _holdFor = Duration(seconds: 5);
  static const _pingEvery = Duration(milliseconds: 2500);
  static const _burstGap = Duration(seconds: 6);

  final SupabaseClient _client;
  final String _conversationId;
  final String _myId;
  final String _myName;
  late final RealtimeChannel _channel;
  late final Timer _tick;
  final _random = Random();
  final _others = <String, TypingEntry>{};
  final _controller = StreamController<List<TypingEntry>>.broadcast();

  DateTime _lastPing = DateTime(0);
  int _myPhrase = 0;
  String? _myActivity;

  Stream<List<TypingEntry>> get stream => _controller.stream;
  List<TypingEntry> get current => _others.values.toList(growable: false);

  void _onEvent(Map<String, dynamic> raw) {
    // supabase_flutter отдаёт либо сам payload, либо обёртку {payload: …}.
    final payload = (raw['payload'] is Map ? raw['payload'] as Map : raw).cast<String, dynamic>();
    final id = payload['uid'] as String?;
    if (id == null || id == _myId) return;
    _others[id] = TypingEntry(
      profileId: id,
      name: (payload['name'] as String?) ?? 'Кто-то',
      phrase: (payload['p'] as num?)?.toInt() ?? 0,
      until: DateTime.now().add(_holdFor),
      activity: payload['a'] as String?,
    );
    _emit();
  }

  /// Вызывается на каждое изменение текста; сама решает, пора ли сообщать.
  /// [activity] — отправляется вложение (MessageKind.wire): у собеседника
  /// вместо «печатает» будет «отправляет фото…» и т. п.
  void ping({String? activity}) {
    final now = DateTime.now();
    if (now.difference(_lastPing) < _pingEvery && activity == _myActivity) return;
    _myActivity = activity;
    // Новый «заход» набора — новая фраза.
    if (now.difference(_lastPing) > _burstGap) _myPhrase = _random.nextInt(typingPhrases.length);
    _lastPing = now;
    unawaited(
      _channel
          .sendBroadcastMessage(
            event: 'typing',
            payload: {'uid': _myId, 'name': _myName, 'p': _myPhrase, 'a': ?activity},
          )
          .catchError((Object error) {
            AppLog.add('Набор не отправился: $error');
            return ChannelResponse.error;
          }),
    );
  }

  /// Сообщение отправлено — «печатает» у собеседника гаснет сразу, а не через
  /// пять секунд. Следующий набор начнёт новую фразу.
  void stop() {
    _lastPing = DateTime(0);
    _myActivity = null;
  }

  void _prune() {
    final now = DateTime.now();
    final before = _others.length;
    _others.removeWhere((_, e) => e.until.isBefore(now));
    if (_others.length != before) _emit();
  }

  void _emit() {
    if (!_controller.isClosed) _controller.add(current);
  }

  void dispose() {
    _tick.cancel();
    unawaited(_client.removeChannel(_channel));
    _controller.close();
  }
}

/// null — без сервера (заглушка) или без входа: «печатает» тогда нет.
final typingHubProvider = Provider.autoDispose.family<TypingHub?, String>((ref, conversationId) {
  if (!Env.isConfigured) return null;
  final me = ref.watch(currentUserProvider);
  if (me == null) return null;
  final hub = TypingHub(
    Supabase.instance.client,
    conversationId,
    me.id,
    me.displayName ?? 'Кто-то',
  );
  ref.onDispose(hub.dispose);
  return hub;
});

final typingEntriesProvider =
    StreamProvider.autoDispose.family<List<TypingEntry>, String>((ref, conversationId) {
      final hub = ref.watch(typingHubProvider(conversationId));
      if (hub == null) return const Stream.empty();
      return hub.stream;
    });
