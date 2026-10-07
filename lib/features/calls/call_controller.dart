import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/env.dart';
import '../../core/debug/app_log.dart';
import '../../core/router/app_router.dart';
import 'call_kit.dart';
import 'call_models.dart';

/// Один звонок за раз на телефоне: состояние, WebRTC и сигналы.
///
/// Как соединяются (оба ждут друг друга, поэтому порядок входа не важен):
///  1. Звонящий: `start_call` → сервер будит получателя пушем; звонящий
///     заходит в канал `call:<id>` и слушает гудки.
///  2. Получатель отвечает: `answer_call`, заходит в тот же канал и шлёт
///     `ready`, пока не получит offer (каналы подписываются не мгновенно).
///  3. Звонящий на `ready` шлёт offer, получатель — answer, дальше обмен
///     кандидатами ice. Голос и видео идут напрямую или через свой TURN.
///  4. Трубку кладут через `end_call` + `bye`; изменение строки `calls`
///     ловится Realtime на случай, если `bye` потерялся.
class CallController extends ChangeNotifier {
  CallController(this._ref);

  final Ref _ref;

  CallInfo? call;
  CallPhase phase = CallPhase.idle;
  CallEndReason? endReason;
  DateTime? connectedAt;
  bool muted = false;
  bool speaker = false;
  bool cameraOn = true;
  bool peerCameraOn = true;

  final localRenderer = RTCVideoRenderer();
  final remoteRenderer = RTCVideoRenderer();
  bool _renderersReady = false;
  bool get hasRemoteVideo => remoteRenderer.srcObject != null;

  RTCPeerConnection? _pc;
  MediaStream? _local;
  RealtimeChannel? _signals;
  RealtimeChannel? _row;
  final _pendingIce = <RTCIceCandidate>[];
  bool _remoteSet = false;
  bool _offerSent = false;
  bool _iceRestarted = false;
  Timer? _ringTimeout;
  Timer? _readyPinger;
  Timer? _connectTimeout;
  Timer? _dropTimer;
  Timer? _ticker;
  AudioPlayer? _ringback;
  StreamSubscription<CallEvent?>? _kitEvents;
  bool _started = false;

  static const _dialFor = Duration(seconds: 45);
  static const _connectFor = Duration(seconds: 30);
  static const _recoverFor = Duration(seconds: 15);

  SupabaseClient get _client => Supabase.instance.client;

  /// Идёт звонок (или вот-вот начнётся) — второй не начать.
  bool get busy => phase != CallPhase.idle && phase != CallPhase.ended;

  Duration get talked => connectedAt == null ? Duration.zero : DateTime.now().difference(connectedAt!);

  // ── запуск ──────────────────────────────────────────────────────────────

  /// Из оболочки вкладок после входа: слушать звонилку и подхватить звонок,
  /// на который ответили, пока приложение ещё запускалось.
  Future<void> start() async {
    if (_started || !CallKit.supported || !Env.isConfigured) return;
    _started = true;
    _kitEvents = FlutterCallkitIncoming.onEvent.listen(_onKitEvent);
    final accepted = await CallKit.acceptedCall();
    if (accepted != null) {
      unawaited(accept(accepted));
    } else {
      unawaited(CallKit.ensurePermissions());
    }
  }

  void _onKitEvent(CallEvent? event) {
    switch (event) {
      case CallEventActionCallAccept(:final callKitParams):
        final info = CallInfo.fromPush(Map<String, dynamic>.from(callKitParams.extra ?? const {}));
        if (info != null) unawaited(accept(info));
      case CallEventActionCallDecline(:final callKitParams):
        unawaited(_endOnServer(callKitParams.id));
      case CallEventActionCallEnded(:final callKitParams):
        // «Завершить» в шторке во время разговора.
        if (call?.id == callKitParams.id && busy) unawaited(hangUp());
      default:
        break;
    }
  }

  /// Пуш о звонке, пока приложение открыто (PushService._onForeground).
  void onPush(Map<String, dynamic> data) {
    final id = data['call_id'];
    if (id is! String) return;
    switch (data['type']) {
      case 'call':
        if (call?.id == id) return;
        final info = CallInfo.fromPush(data);
        if (info != null) unawaited(CallKit.showIncoming(info));
      case 'call_update':
        // Свой текущий звонок ведёт сам контроллер (Realtime и bye).
        if (call?.id == id && busy) return;
        unawaited(CallKit.end(id));
        if (data['status'] == 'missed' || data['status'] == 'cancelled') {
          final info = CallInfo.fromPush(data);
          if (info != null) unawaited(CallKit.showMissed(info));
        }
    }
  }

  // ── исходящий ───────────────────────────────────────────────────────────

  /// Позвонить в личный чат. Экран звонка открывается сразу, а сервер и
  /// камера догоняют.
  Future<void> dial({
    required String conversationId,
    required String peerId,
    required String peerName,
    String? peerAvatarUrl,
    required bool video,
  }) async {
    if (busy) return;
    _reset();
    call = CallInfo(
      id: '',
      conversationId: conversationId,
      peerId: peerId,
      peerName: peerName,
      peerAvatarUrl: peerAvatarUrl,
      video: video,
      outgoing: true,
    );
    cameraOn = video;
    speaker = video;
    phase = CallPhase.dialing;
    notifyListeners();
    _openScreen();

    final String id;
    try {
      final result = Map<String, dynamic>.from(
        await _client.rpc('start_call', params: {'in_conversation': conversationId, 'in_video': video}) as Map,
      );
      id = result['id'] as String;
      call = CallInfo(
        id: id,
        conversationId: conversationId,
        peerId: peerId,
        peerName: peerName,
        peerAvatarUrl: peerAvatarUrl,
        video: video,
        outgoing: true,
      );
      if (result['status'] == 'busy') {
        _finish(CallEndReason.busy);
        return;
      }
    } catch (error) {
      AppLog.add('Звонок не начался: $error');
      _finish(CallEndReason.unavailable);
      return;
    }
    if (phase != CallPhase.dialing) {
      // Положили трубку, пока сервер отвечал.
      unawaited(_endOnServer(id));
      return;
    }

    if (!await _prepare()) {
      unawaited(_endOnServer(id));
      return;
    }
    _listen(id);
    unawaited(CallKit.startOutgoing(call!));
    unawaited(_playRingback());
    _ringTimeout = Timer(_dialFor, () {
      if (phase == CallPhase.dialing) unawaited(hangUp(timeout: true));
    });
  }

  // ── входящий ────────────────────────────────────────────────────────────

  /// Ответили в звонилке.
  Future<void> accept(CallInfo info) async {
    if (call?.id == info.id && busy) return;
    if (busy) {
      // Уже разговариваем — второй звонок сбрасываем.
      unawaited(_endOnServer(info.id));
      unawaited(CallKit.end(info.id));
      return;
    }
    _reset();
    call = info;
    cameraOn = info.video;
    speaker = info.video;
    phase = CallPhase.connecting;
    notifyListeners();
    _openScreen();

    try {
      final ok = await _client.rpc('answer_call', params: {'in_call': info.id});
      if (ok != true) {
        _finish(CallEndReason.cancelled);
        return;
      }
    } catch (error) {
      AppLog.add('Ответ на звонок не дошёл: $error');
      _finish(CallEndReason.failed);
      return;
    }

    if (!await _prepare()) {
      unawaited(_endOnServer(info.id));
      return;
    }
    _listen(info.id);
    _connectTimeout = Timer(_connectFor, () {
      if (phase == CallPhase.connecting) unawaited(hangUp(reason: CallEndReason.failed));
    });
    // Звонящий шлёт offer по ready; повторяем, пока не придёт.
    _sendReady();
    _readyPinger = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      if (_remoteSet || phase != CallPhase.connecting) {
        _readyPinger?.cancel();
      } else {
        _sendReady();
      }
    });
  }

  // ── положить трубку и кнопки ───────────────────────────────────────────

  Future<void> hangUp({bool timeout = false, CallEndReason? reason}) async {
    final current = call;
    if (current == null || !busy) return;
    if (current.id.isNotEmpty) {
      _send(CallSignal.bye, const {});
      unawaited(_endOnServer(current.id, timeout: timeout));
    }
    _finish(reason ?? (timeout ? CallEndReason.noAnswer : CallEndReason.hangUp));
  }

  void toggleMute() {
    muted = !muted;
    for (final track in _local?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      track.enabled = !muted;
    }
    notifyListeners();
  }

  Future<void> toggleSpeaker() async {
    speaker = !speaker;
    await _applySpeaker();
    notifyListeners();
  }

  void toggleCamera() {
    final tracks = _local?.getVideoTracks() ?? const <MediaStreamTrack>[];
    if (tracks.isEmpty) return;
    cameraOn = !cameraOn;
    for (final track in tracks) {
      track.enabled = cameraOn;
    }
    _send(CallSignal.cam, {'on': cameraOn});
    notifyListeners();
  }

  Future<void> switchCamera() async {
    final track = _local?.getVideoTracks().firstOrNull;
    if (track == null) return;
    try {
      await Helper.switchCamera(track);
    } catch (error) {
      AppLog.add('Камера не переключилась: $error');
    }
  }

  // ── WebRTC ──────────────────────────────────────────────────────────────

  /// Микрофон (и камера), соединение. false — без микрофона не звоним.
  Future<bool> _prepare() async {
    final current = call!;
    try {
      if (!_renderersReady) {
        await localRenderer.initialize();
        await remoteRenderer.initialize();
        _renderersReady = true;
      }
      _local = await navigator.mediaDevices.getUserMedia({
        'audio': {'echoCancellation': true, 'noiseSuppression': true, 'autoGainControl': true},
        'video': current.video
            ? {'facingMode': 'user', 'width': 1280, 'height': 720, 'frameRate': 24}
            : false,
      });
    } catch (error) {
      AppLog.add('Нет доступа к микрофону/камере: $error');
      _finish(CallEndReason.noMicrophone);
      return false;
    }
    if (!busy) {
      _stopLocal();
      return false;
    }
    localRenderer.srcObject = current.video ? _local : null;

    try {
      final pc = await createPeerConnection({
        ...await _iceConfig(),
        'sdpSemantics': 'unified-plan',
      });
      _pc = pc;
      pc.onIceCandidate = (candidate) {
        if (candidate.candidate == null) return;
        _send(CallSignal.ice, {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        });
      };
      pc.onTrack = (event) {
        if (event.streams.isEmpty) return;
        remoteRenderer.srcObject = event.streams.first;
        notifyListeners();
      };
      pc.onConnectionState = _onConnectionState;
      for (final track in _local!.getTracks()) {
        await pc.addTrack(track, _local!);
      }
      await _applySpeaker();
      return true;
    } catch (error) {
      AppLog.add('Соединение для звонка не создалось: $error');
      _finish(CallEndReason.failed);
      return false;
    }
  }

  void _onConnectionState(RTCPeerConnectionState state) {
    switch (state) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        _dropTimer?.cancel();
        _connectTimeout?.cancel();
        if (phase == CallPhase.connecting || phase == CallPhase.reconnecting || phase == CallPhase.dialing) {
          connectedAt ??= DateTime.now();
          phase = CallPhase.active;
          unawaited(_stopRingback());
          final id = call?.id;
          if (id != null && id.isNotEmpty) unawaited(CallKit.connected(id));
          // Системная звонилка при соединении сама переключает звук на разговорный
          // динамик; выбранный человеком маршрут возвращаем после неё.
          for (final delay in const [0, 600, 1800]) {
            Timer(Duration(milliseconds: delay), () {
              if (phase == CallPhase.active) unawaited(_applySpeaker());
            });
          }
          _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) => notifyListeners());
          notifyListeners();
        }
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        if (phase != CallPhase.active) return;
        phase = CallPhase.reconnecting;
        notifyListeners();
        _dropTimer?.cancel();
        _dropTimer = Timer(_recoverFor, () {
          if (phase == CallPhase.reconnecting) unawaited(hangUp(reason: CallEndReason.failed));
        });
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        // Сменилась сеть (Wi-Fi → мобильная): звонящий один раз пересобирает
        // путь; не вышло — звонок кончился.
        if (call?.outgoing == true && !_iceRestarted) {
          _iceRestarted = true;
          unawaited(_sendOffer(restart: true));
        } else if (busy) {
          unawaited(hangUp(reason: CallEndReason.failed));
        }
      default:
        break;
    }
  }

  Future<void> _sendOffer({bool restart = false}) async {
    final pc = _pc;
    if (pc == null) return;
    try {
      if (_offerSent && !restart) {
        // Получатель переспрашивает — повторяем то же описание.
        final local = await pc.getLocalDescription();
        if (local != null) _send(CallSignal.offer, {'sdp': local.sdp, 'type': local.type});
        return;
      }
      final offer = await pc.createOffer({if (restart) 'iceRestart': true});
      await pc.setLocalDescription(offer);
      _offerSent = true;
      _send(CallSignal.offer, {'sdp': offer.sdp, 'type': offer.type});
    } catch (error) {
      AppLog.add('Offer не отправился: $error');
    }
  }

  Future<void> _onOffer(Map<String, dynamic> payload) async {
    final pc = _pc;
    if (pc == null || call?.outgoing != false) return;
    // Повтор того же offer после ready — уже ответили. Новый (после смены
    // сети) отличается описанием и принимается заново.
    if (_remoteSet) {
      final current = await pc.getRemoteDescription();
      if (current?.sdp == payload['sdp']) return;
    }
    try {
      await pc.setRemoteDescription(RTCSessionDescription(payload['sdp'] as String?, payload['type'] as String?));
      _remoteSet = true;
      _readyPinger?.cancel();
      await _flushIce();
      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      _send(CallSignal.answer, {'sdp': answer.sdp, 'type': answer.type});
    } catch (error) {
      AppLog.add('Offer не принят: $error');
    }
  }

  Future<void> _onAnswer(Map<String, dynamic> payload) async {
    final pc = _pc;
    if (pc == null || call?.outgoing != true) return;
    try {
      final state = pc.signalingState;
      if (state != RTCSignalingState.RTCSignalingStateHaveLocalOffer) return;
      await pc.setRemoteDescription(RTCSessionDescription(payload['sdp'] as String?, payload['type'] as String?));
      _remoteSet = true;
      await _flushIce();
    } catch (error) {
      AppLog.add('Answer не принят: $error');
    }
  }

  Future<void> _onIce(Map<String, dynamic> payload) async {
    final candidate = RTCIceCandidate(
      payload['candidate'] as String?,
      payload['sdpMid'] as String?,
      (payload['sdpMLineIndex'] as num?)?.toInt(),
    );
    if (_remoteSet && _pc != null) {
      try {
        await _pc!.addCandidate(candidate);
      } catch (error) {
        AppLog.add('Кандидат не добавился: $error');
      }
    } else {
      _pendingIce.add(candidate);
    }
  }

  Future<void> _flushIce() async {
    final pending = List.of(_pendingIce);
    _pendingIce.clear();
    for (final candidate in pending) {
      try {
        await _pc?.addCandidate(candidate);
      } catch (error) {
        AppLog.add('Кандидат не добавился: $error');
      }
    }
  }

  /// STUN/TURN с сервера (временный логин к своему TURN на ВМ). Кешируется
  /// на полсуток: логин живёт сутки.
  static Map<String, dynamic>? _iceCache;
  static DateTime _iceCacheUntil = DateTime(0);

  Future<Map<String, dynamic>> _iceConfig() async {
    if (_iceCache != null && DateTime.now().isBefore(_iceCacheUntil)) return _iceCache!;
    try {
      final result = Map<String, dynamic>.from(await _client.rpc('turn_credentials') as Map);
      _iceCache = {'iceServers': result['iceServers']};
      _iceCacheUntil = DateTime.now().add(const Duration(hours: 12));
      return _iceCache!;
    } catch (error) {
      AppLog.add('TURN недоступен: $error');
      return _iceCache ??
          const {
            'iceServers': [
              {'urls': 'stun:api-socialworld.deepdrift.tech:3478'},
            ],
          };
    }
  }

  static const _device = MethodChannel('chawo/device');

  /// Сначала через системный Telecom (он держит маршрут звука звонка и
  /// перебивает обычный AudioManager), затем WebRTC-способом — на случай,
  /// если звонок идёт без Telecom.
  Future<void> _applySpeaker() async {
    if (kIsWeb) return;
    final id = call?.id;
    try {
      if (id != null) {
        final routed = await _device.invokeMethod<bool>('callAudioRoute', {'callId': id, 'speaker': speaker});
        if (routed == true) return;
      }
    } catch (error) {
      AppLog.add('Telecom: динамик не переключился: $error');
    }
    try {
      await Helper.setSpeakerphoneOn(speaker);
    } catch (error) {
      AppLog.add('Динамик не переключился: $error');
    }
  }

  // ── сигналы ─────────────────────────────────────────────────────────────

  void _listen(String id) {
    final signals = _client.channel('call:$id');
    _signals = signals;
    signals
        .onBroadcast(event: 'sig', callback: _onSignal)
        .subscribe((status, error) {
          if (status == RealtimeSubscribeStatus.subscribed && call?.outgoing == false && !_remoteSet) {
            _sendReady();
          }
        });

    final row = _client.channel('call-row:$id');
    _row = row;
    row
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'calls',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: id),
          callback: (change) => _onRow(change.newRecord),
        )
        .subscribe();
  }

  void _onSignal(Map<String, dynamic> raw) {
    final payload = (raw['payload'] is Map ? raw['payload'] as Map : raw).cast<String, dynamic>();
    // Свои же сообщения Realtime не возвращает, но на всякий случай.
    if (payload['from'] == _client.auth.currentUser?.id) return;
    final data = (payload['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    switch (payload['kind']) {
      case CallSignal.ready:
        if (call?.outgoing != true) return;
        _ringTimeout?.cancel();
        unawaited(_stopRingback());
        if (phase == CallPhase.dialing) {
          phase = CallPhase.connecting;
          _connectTimeout = Timer(_connectFor, () {
            if (phase == CallPhase.connecting) unawaited(hangUp(reason: CallEndReason.failed));
          });
          notifyListeners();
        }
        unawaited(_sendOffer());
      case CallSignal.offer:
        unawaited(_onOffer(data));
      case CallSignal.answer:
        unawaited(_onAnswer(data));
      case CallSignal.ice:
        unawaited(_onIce(data));
      case CallSignal.cam:
        peerCameraOn = data['on'] != false;
        notifyListeners();
      case CallSignal.bye:
        if (busy) _finish(CallEndReason.hangUp);
    }
  }

  void _onRow(Map<String, dynamic> row) {
    final status = row['status'] as String?;
    final current = call;
    if (current == null || !busy) return;
    if (status == 'active' && phase == CallPhase.dialing) {
      // Ответили — гудки больше не нужны, ждём ready.
      _ringTimeout?.cancel();
      unawaited(_stopRingback());
      phase = CallPhase.connecting;
      notifyListeners();
      return;
    }
    if (status != null && status != 'ringing' && status != 'active') {
      _finish(CallEndReason.fromStatus(status, outgoing: current.outgoing));
    }
  }

  void _sendReady() => _send(CallSignal.ready, const {});

  void _send(String kind, Map<String, dynamic> data) {
    final signals = _signals;
    if (signals == null) return;
    unawaited(
      signals
          .sendBroadcastMessage(
            event: 'sig',
            payload: {'kind': kind, 'from': _client.auth.currentUser?.id, 'data': data},
          )
          .catchError((Object error) {
            AppLog.add('Сигнал звонка ($kind) не ушёл: $error');
            return ChannelResponse.error;
          }),
    );
  }

  Future<void> _endOnServer(String id, {bool timeout = false}) async {
    try {
      await _client.rpc('end_call', params: {'in_call': id, 'in_reason': timeout ? 'timeout' : null});
    } catch (error) {
      AppLog.add('Звонок не завершился на сервере: $error');
    }
  }

  // ── гудки ───────────────────────────────────────────────────────────────

  Future<void> _playRingback() async {
    try {
      final player = _ringback ??= AudioPlayer()
        ..setAudioContext(
          AudioContext(
            android: const AudioContextAndroid(
              audioFocus: AndroidAudioFocus.gainTransient,
              usageType: AndroidUsageType.voiceCommunication,
              contentType: AndroidContentType.speech,
            ),
          ),
        )
        ..setReleaseMode(ReleaseMode.loop);
      await player.play(AssetSource('sounds/ringback.wav'), volume: 0.6);
    } catch (error) {
      AppLog.add('Гудки не играют: $error');
    }
  }

  Future<void> _stopRingback() async {
    try {
      await _ringback?.stop();
    } catch (_) {}
  }

  // ── конец ───────────────────────────────────────────────────────────────

  void _openScreen() {
    try {
      _ref.read(routerProvider).push(Routes.call);
    } catch (error) {
      AppLog.add('Экран звонка не открылся: $error');
    }
  }

  void _finish(CallEndReason reason) {
    if (phase == CallPhase.ended || phase == CallPhase.idle) return;
    endReason = reason;
    phase = CallPhase.ended;
    final id = call?.id;
    _cancelTimers();
    unawaited(_stopRingback());
    _teardown();
    if (id != null && id.isNotEmpty) unawaited(CallKit.end(id));
    if (reason == CallEndReason.busy || reason == CallEndReason.noAnswer || reason == CallEndReason.declined) {
      HapticFeedback.heavyImpact();
    }
    notifyListeners();
    // Подпись «Звонок завершён» видна пару секунд, потом экран закрывается.
    Timer(const Duration(seconds: 2), () {
      if (phase != CallPhase.ended) return;
      phase = CallPhase.idle;
      notifyListeners();
    });
  }

  void _cancelTimers() {
    for (final timer in [_ringTimeout, _readyPinger, _connectTimeout, _dropTimer, _ticker]) {
      timer?.cancel();
    }
    _ticker = null;
  }

  void _stopLocal() {
    for (final track in _local?.getTracks() ?? const <MediaStreamTrack>[]) {
      unawaited(track.stop());
    }
    unawaited(_local?.dispose());
    _local = null;
  }

  void _teardown() {
    _stopLocal();
    localRenderer.srcObject = null;
    remoteRenderer.srcObject = null;
    final pc = _pc;
    _pc = null;
    if (pc != null) {
      unawaited(pc.close().then((_) => pc.dispose()).catchError((Object _) {}));
    }
    for (final channel in [_signals, _row]) {
      if (channel != null) unawaited(_client.removeChannel(channel));
    }
    _signals = null;
    _row = null;
    if (!kIsWeb) unawaited(Helper.setSpeakerphoneOn(false).catchError((Object _) {}));
  }

  void _reset() {
    _cancelTimers();
    _pendingIce.clear();
    _remoteSet = false;
    _offerSent = false;
    _iceRestarted = false;
    endReason = null;
    connectedAt = null;
    muted = false;
    peerCameraOn = true;
  }

  @override
  void dispose() {
    _kitEvents?.cancel();
    _cancelTimers();
    _teardown();
    unawaited(_ringback?.dispose());
    if (_renderersReady) {
      unawaited(localRenderer.dispose());
      unawaited(remoteRenderer.dispose());
    }
    super.dispose();
  }
}

final callControllerProvider = Provider<CallController>((ref) {
  ref.keepAlive();
  final controller = CallController(ref);
  ref.onDispose(controller.dispose);
  return controller;
});
