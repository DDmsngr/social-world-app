import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/env.dart';
import '../../../core/debug/app_log.dart';
import '../data/secure_chat_repository.dart';
import '../presentation/providers/chat_providers.dart';

/// Точка трансляции. В личном чате приезжает зашифрованной и расшифровывается
/// на телефоне, в группе — открытой.
class LivePoint {
  const LivePoint({required this.lat, required this.lng, this.accuracy});

  final double lat;
  final double lng;
  final double? accuracy;

  String encode() => jsonEncode({'lat': lat, 'lng': lng, if (accuracy != null) 'acc': accuracy});

  static LivePoint? decode(String? json) {
    if (json == null) return null;
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      return LivePoint(
        lat: (map['lat'] as num).toDouble(),
        lng: (map['lng'] as num).toDouble(),
        accuracy: (map['acc'] as num?)?.toDouble(),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Трансляция одного человека в чате (строка live_locations, 0060).
class LiveShare {
  const LiveShare({
    required this.id,
    required this.conversationId,
    required this.userId,
    required this.startedAt,
    this.expiresAt,
    this.updatedAt,
    this.point,
  });

  final String id;
  final String conversationId;
  final String userId;
  final DateTime startedAt;

  /// null — «пока не выключу».
  final DateTime? expiresAt;
  final DateTime? updatedAt;
  final LivePoint? point;
}

/// «ещё 12 мин», «до 19:30», «пока не выключит».
String liveRemainingLabel(LiveShare share, DateTime now) {
  final until = share.expiresAt;
  if (until == null) return 'пока не выключит';
  final left = until.difference(now);
  if (left.inMinutes < 60) return 'ещё ${left.inMinutes.clamp(1, 59)} мин';
  return 'до ${until.hour.toString().padLeft(2, '0')}:${until.minute.toString().padLeft(2, '0')}';
}

/// «обновлено только что», «обновлено 3 мин назад».
String liveUpdatedLabel(DateTime? updatedAt, DateTime now) {
  if (updatedAt == null) return 'ждём первую точку';
  final ago = now.difference(updatedAt);
  if (ago.inSeconds < 45) return 'обновлено только что';
  if (ago.inMinutes < 60) return 'обновлено ${ago.inMinutes.clamp(1, 59)} мин назад';
  return 'обновлено давно';
}

bool _isActive(Map<String, dynamic> row, DateTime now) {
  if (row['stopped_at'] != null) return false;
  final until = row['expires_at'] as String?;
  return until == null || DateTime.parse(until).isAfter(now);
}

/// Идущие сейчас трансляции чата, живые (Realtime).
final liveSharesProvider = StreamProvider.autoDispose.family<List<LiveShare>, String>((ref, conversationId) {
  if (!Env.isConfigured) return Stream.value(const []);
  final repo = ref.read(chatRepositoryProvider);
  return Supabase.instance.client
      .from('live_locations')
      .stream(primaryKey: ['id'])
      .eq('conversation_id', conversationId)
      .order('started_at', ascending: false)
      .limit(30)
      .asyncMap((rows) async {
        final now = DateTime.now();
        final shares = <LiveShare>[];
        for (final row in rows) {
          if (!_isActive(row, now)) continue;
          LivePoint? point;
          if (row['lat'] != null && row['lng'] != null) {
            point = LivePoint(
              lat: (row['lat'] as num).toDouble(),
              lng: (row['lng'] as num).toDouble(),
              accuracy: (row['accuracy'] as num?)?.toDouble(),
            );
          } else if (row['ciphertext'] != null && repo is SecureChatRepository) {
            try {
              point = LivePoint.decode(await repo.openLiveLocation(conversationId, row));
            } catch (error) {
              AppLog.add('Геопозиция не расшифровалась: $error');
            }
          }
          shares.add(
            LiveShare(
              id: row['id'] as String,
              conversationId: conversationId,
              userId: row['user_id'] as String,
              startedAt: DateTime.parse(row['started_at'] as String).toLocal(),
              expiresAt: row['expires_at'] == null ? null : DateTime.parse(row['expires_at'] as String).toLocal(),
              updatedAt: row['updated_at'] == null ? null : DateTime.parse(row['updated_at'] as String).toLocal(),
              point: point,
            ),
          );
        }
        return shares;
      });
});

class _Outgoing {
  _Outgoing(this.shareId, this.expiresAt);

  final String shareId;
  final DateTime? expiresAt;
  DateTime? sentAt;
  Position? sentFrom;
}

/// Отправка своей геопозиции во все чаты, где она сейчас транслируется.
/// Один поток GPS на все трансляции; пока он идёт, Android держит службу с
/// уведомлением «ChaWo транслирует геопозицию» — точки уходят и при
/// свёрнутом приложении.
class LiveLocationSharer extends ChangeNotifier {
  LiveLocationSharer(this._ref);

  final Ref _ref;
  final _active = <String, _Outgoing>{};
  StreamSubscription<Position>? _gps;
  Timer? _heartbeat;
  Position? _last;

  SupabaseClient get _client => Supabase.instance.client;

  bool isSharing(String conversationId) => _active.containsKey(conversationId);

  /// Новая точка уходит, если сдвинулись дальше [minMove] метров или с
  /// прошлой прошло [maxQuiet] — чтобы у собеседника не висело «обновлено
  /// давно», пока человек стоит на месте.
  static const minMove = 20.0;
  static const maxQuiet = Duration(seconds: 30);

  static bool shouldSend({
    required DateTime? lastSentAt,
    required double? movedMeters,
    required DateTime now,
  }) {
    if (lastSentAt == null || movedMeters == null) return true;
    return movedMeters >= minMove || now.difference(lastSentAt) >= maxQuiet;
  }

  /// [minutes] null — пока не выключу. Разрешение на геолокацию должно быть
  /// уже выдано (экран спрашивает его до вызова).
  Future<void> start(String conversationId, int? minutes, Position first) async {
    final id = await _client.rpc(
      'start_live_location',
      params: {'in_conversation': conversationId, 'in_minutes': minutes},
    ) as String;
    _active[conversationId] = _Outgoing(
      id,
      minutes == null ? null : DateTime.now().add(Duration(minutes: minutes)),
    );
    _last = first;
    notifyListeners();
    await _send(conversationId, first);
    _ensureGps();
  }

  Future<void> stop(String conversationId) async {
    final out = _active.remove(conversationId);
    notifyListeners();
    if (_active.isEmpty) _stopGps();
    if (out == null) return;
    try {
      await _client.rpc('stop_live_location', params: {'in_id': out.shareId});
    } catch (error) {
      AppLog.add('Трансляция не остановилась на сервере: $error');
    }
  }

  /// После перезапуска приложения: свои незакрытые трансляции продолжаются.
  Future<void> resumeMine() async {
    if (!Env.isConfigured) return;
    final me = _client.auth.currentUser?.id;
    if (me == null) return;
    try {
      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.always && permission != LocationPermission.whileInUse) return;
      final rows = await _client
          .from('live_locations')
          .select('id, conversation_id, expires_at, stopped_at')
          .eq('user_id', me)
          .isFilter('stopped_at', null);
      final now = DateTime.now();
      for (final row in rows) {
        if (!_isActive(row, now)) continue;
        _active[row['conversation_id'] as String] = _Outgoing(
          row['id'] as String,
          row['expires_at'] == null ? null : DateTime.parse(row['expires_at'] as String).toLocal(),
        );
      }
      if (_active.isNotEmpty) {
        notifyListeners();
        _ensureGps();
      }
    } catch (error) {
      AppLog.add('Трансляции геопозиции не возобновились: $error');
    }
  }

  void _ensureGps() {
    if (_gps != null) return;
    final settings = defaultTargetPlatform == TargetPlatform.android
        ? AndroidSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 10,
            intervalDuration: const Duration(seconds: 10),
            foregroundNotificationConfig: const ForegroundNotificationConfig(
              notificationTitle: 'ChaWo транслирует геопозицию',
              notificationText: 'Собеседники видят, где вы. Выключить можно в чате.',
              notificationChannelName: 'Трансляция геопозиции',
              enableWakeLock: true,
              setOngoing: true,
            ),
          )
        : const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10);
    _gps = Geolocator.getPositionStream(locationSettings: settings).listen(
      (position) {
        _last = position;
        _sendAll(position);
      },
      onError: (Object error) => AppLog.add('GPS трансляции: $error'),
    );
    _heartbeat = Timer.periodic(maxQuiet, (_) {
      final last = _last;
      if (last != null) _sendAll(last);
    });
  }

  void _stopGps() {
    _gps?.cancel();
    _gps = null;
    _heartbeat?.cancel();
    _heartbeat = null;
  }

  void _sendAll(Position position) {
    for (final conversationId in [..._active.keys]) {
      unawaited(_send(conversationId, position));
    }
  }

  Future<void> _send(String conversationId, Position position) async {
    final out = _active[conversationId];
    if (out == null) return;
    final now = DateTime.now();
    final until = out.expiresAt;
    if (until != null && !until.isAfter(now)) {
      _active.remove(conversationId);
      notifyListeners();
      if (_active.isEmpty) _stopGps();
      return;
    }
    final from = out.sentFrom;
    final moved = from == null
        ? null
        : Geolocator.distanceBetween(from.latitude, from.longitude, position.latitude, position.longitude);
    if (!shouldSend(lastSentAt: out.sentAt, movedMeters: moved, now: now)) return;
    out
      ..sentAt = now
      ..sentFrom = position;

    final point = LivePoint(lat: position.latitude, lng: position.longitude, accuracy: position.accuracy);
    try {
      final repo = _ref.read(chatRepositoryProvider);
      final sealed = repo is SecureChatRepository
          ? await repo.sealLiveLocation(conversationId, out.shareId, point.encode())
          : null;
      final ok = await _client.rpc(
        'update_live_location',
        params: {
          'in_id': out.shareId,
          if (sealed != null) ...{
            'in_ciphertext': sealed['ciphertext'],
            'in_nonce': sealed['nonce'],
            'in_mac': sealed['mac'],
            'in_signature': sealed['signature'],
          } else ...{
            'in_lat': point.lat,
            'in_lng': point.lng,
            'in_accuracy': point.accuracy,
          },
        },
      );
      // Сервер говорит, что трансляция кончилась (истекла или выключена на
      // другом телефоне) — больше не шлём.
      if (ok == false && _active[conversationId] == out) {
        _active.remove(conversationId);
        notifyListeners();
        if (_active.isEmpty) _stopGps();
      }
    } catch (error) {
      AppLog.add('Точка трансляции не ушла: $error');
    }
  }

  @override
  void dispose() {
    _stopGps();
    super.dispose();
  }
}

/// Экраны слушают его через ListenableBuilder — как CallController.
final liveLocationSharerProvider = Provider<LiveLocationSharer>((ref) {
  ref.keepAlive();
  final sharer = LiveLocationSharer(ref);
  ref.onDispose(sharer.dispose);
  return sharer;
});
