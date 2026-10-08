import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/debug/app_log.dart';
import '../../domain/entities/city_route.dart';

enum RecordingStatus {
  /// Ещё не начинали или уже всё сбросили.
  idle,

  /// Ждём ответа на запрос разрешения.
  preparing,

  recording,
  paused,

  /// Разрешение не дали — без него записывать нечего.
  denied,

  failed,
}

class RouteRecordingState {
  const RouteRecordingState({
    this.status = RecordingStatus.idle,
    this.path = const [],
    this.photos = const [],
    this.distanceMeters = 0,
    this.startedAt,
    this.elapsed = Duration.zero,
    this.limit,
    this.error,
  });

  final RecordingStatus status;
  final List<RouteCoordinate> path;
  final List<PendingRoutePhoto> photos;
  final int distanceMeters;
  final DateTime? startedAt;
  final Duration elapsed;

  /// Ограничение записи по времени; null — пишем, пока не остановят.
  final Duration? limit;
  final String? error;

  bool get isActive =>
      status == RecordingStatus.recording || status == RecordingStatus.paused;

  /// Меньше двух точек — это не маршрут, а одна отметка на карте.
  bool get canPublish => path.length >= 2;

  RouteCoordinate? get lastPoint => path.isEmpty ? null : path.last;

  RouteRecordingState copyWith({
    RecordingStatus? status,
    List<RouteCoordinate>? path,
    List<PendingRoutePhoto>? photos,
    int? distanceMeters,
    DateTime? startedAt,
    Duration? elapsed,
    Duration? limit,
    bool clearLimit = false,
    String? error,
  }) => RouteRecordingState(
    status: status ?? this.status,
    path: path ?? this.path,
    photos: photos ?? this.photos,
    distanceMeters: distanceMeters ?? this.distanceMeters,
    startedAt: startedAt ?? this.startedAt,
    elapsed: elapsed ?? this.elapsed,
    limit: clearLimit ? null : (limit ?? this.limit),
    error: error,
  );

  Map<String, dynamic> toJson() => {
    'path': [
      for (final p in path) [p.latitude, p.longitude],
    ],
    'photos': [
      for (final photo in photos)
        {
          'path': photo.localPath,
          'lat': photo.latitude,
          'lng': photo.longitude,
          'at': photo.takenAt.toIso8601String(),
        },
    ],
    'distance': distanceMeters,
    'startedAt': startedAt?.toIso8601String(),
    'elapsed': elapsed.inSeconds,
  };

  /// Черновик, восстановленный после перезапуска: на паузе, лимит снят.
  static RouteRecordingState fromJson(Map<String, dynamic> json) =>
      RouteRecordingState(
        status: RecordingStatus.paused,
        path: [
          for (final p in (json['path'] as List).cast<List<dynamic>>())
            RouteCoordinate((p[0] as num).toDouble(), (p[1] as num).toDouble()),
        ],
        photos: [
          for (final raw in (json['photos'] as List? ?? const []).cast<Map<String, dynamic>>())
            PendingRoutePhoto(
              localPath: raw['path'] as String,
              latitude: (raw['lat'] as num).toDouble(),
              longitude: (raw['lng'] as num).toDouble(),
              takenAt: DateTime.parse(raw['at'] as String),
            ),
        ],
        distanceMeters: (json['distance'] as num?)?.toInt() ?? 0,
        startedAt: json['startedAt'] == null
            ? null
            : DateTime.parse(json['startedAt'] as String),
        elapsed: Duration(seconds: (json['elapsed'] as num?)?.toInt() ?? 0),
      );
}

/// Варианты ограничения записи по времени; null — без ограничения.
const routeLimitOptions = <Duration?>[
  null,
  Duration(minutes: 30),
  Duration(hours: 1),
  Duration(hours: 2),
  Duration(hours: 4),
];

String routeLimitLabel(Duration? limit) => switch (limit) {
  null => 'Без ограничения',
  final d when d.inHours == 0 => '${d.inMinutes} мин',
  final d => '${d.inHours} ч',
};

/// Запись маршрута.
///
/// Идёт в фоне: на Android поток координат держит служба переднего плана
/// с уведомлением «Идёт запись маршрута», так что приложение можно свернуть
/// или уйти на другие вкладки. Фоновое разрешение на геопозицию для этого не
/// нужно — служба стартует, пока приложение открыто. Точки сохраняются по
/// ходу: если Android выгрузит приложение, прогулка восстановится на паузе.
class RouteRecorder extends Notifier<RouteRecordingState> {
  static const _prefsKey = 'route_recording_draft';
  /// Точки ближе этого расстояния не пишем: GPS шумит стоя на месте, и без
  /// фильтра трек превращается в клубок вокруг одной точки, а дистанция
  /// накручивается сама по себе.
  static const _minDistanceMeters = 12.0;

  /// Одиночные выбросы (прыжок на сотни метров за секунду) — не движение,
  /// а потеря сигнала. Считаем по скорости, чтобы не отсекать машину.
  static const _maxSpeedMetersPerSecond = 40.0;

  StreamSubscription<Position>? _positions;
  Timer? _ticker;
  Timer? _resubscribe;
  DateTime? _lastSampleAt;
  var _disposed = false;

  @override
  RouteRecordingState build() {
    ref.keepAlive();
    ref.onDispose(() {
      _disposed = true;
      _teardown();
    });
    Future.microtask(_restore);
    return const RouteRecordingState();
  }

  Future<void> start({Duration? limit}) async {
    if (state.status == RecordingStatus.recording) return;

    state = RouteRecordingState(status: RecordingStatus.preparing, limit: limit);

    final allowed = await _ensurePermission();
    // Например, resetSessionScopedProviders успел пересоздать провайдер
    // (выход из аккаунта) прямо во время ожидания разрешения — эта
    // корутина всё ещё держит старый, уже уничтоженный инстанс.
    if (_disposed || !allowed) return;

    final startedAt = DateTime.now();
    state = RouteRecordingState(
      status: RecordingStatus.recording,
      startedAt: startedAt,
      limit: limit,
    );

    _lastSampleAt = startedAt;
    _startTicker();
    AppLog.add('RouteRecorder: запись начата');

    // Первую точку берём отдельным запросом: поток отдаёт координаты только
    // при движении, и без этого карта стоит пустой, пока человек не пройдёт
    // первые метры — выглядит как сломанная запись.
    await _seedFirstPoint();
    if (_disposed) return;
    _listenToPositions();
  }

  void pause() {
    if (state.status != RecordingStatus.recording) return;
    _positions?.pause();
    _ticker?.cancel();
    _ticker = null;
    state = state.copyWith(status: RecordingStatus.paused);
    _save();
    AppLog.add('RouteRecorder: пауза, точек ${state.path.length}');
  }

  void resume() {
    if (state.status != RecordingStatus.paused) return;
    // После паузы разрыв во времени не должен превратиться в «телепорт»:
    // следующую точку считаем от момента возобновления.
    _lastSampleAt = DateTime.now();
    // Обычная пауза держит подписку живой (_positions.pause()), но stop()
    // уже разорвал её (_teardown обнулил _positions) — экран публикации
    // после «Продолжить» вызывает тот же resume(), и .resume() на null
    // молча ничего не делал: таймер шёл, а новые точки не приходили.
    if (_positions == null) {
      _listenToPositions();
    } else {
      _positions!.resume();
    }
    _startTicker();
    // Продолжили после того, как вышло время, — дальше без ограничения,
    // иначе запись тут же остановилась бы снова.
    final limit = state.limit;
    state = state.copyWith(
      status: RecordingStatus.recording,
      clearLimit: limit != null && state.elapsed >= limit,
    );
  }

  /// Останавливает запись, но состояние сохраняет — из него собирается черновик
  /// на экране публикации.
  void stop() {
    _teardown();
    if (!state.isActive) return;
    state = state.copyWith(status: RecordingStatus.paused);
    _save();
    AppLog.add(
      'RouteRecorder: стоп, ${state.path.length} точек, '
      '${state.distanceMeters} м',
    );
  }

  void reset() {
    _teardown();
    state = const RouteRecordingState();
    unawaited(
      SharedPreferences.getInstance().then((prefs) => prefs.remove(_prefsKey)),
    );
  }

  /// Черновик прогулки на диск: переживает выгрузку приложения системой.
  void _save() {
    if (!state.isActive || state.path.isEmpty) return;
    final json = jsonEncode(state.toJson());
    unawaited(
      SharedPreferences.getInstance()
          .then((prefs) => prefs.setString(_prefsKey, json))
          .catchError((Object e) {
            AppLog.add('RouteRecorder: черновик не сохранился — $e');
            return false;
          }),
    );
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || _disposed || state.status != RecordingStatus.idle) return;
      final restored = RouteRecordingState.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      if (restored.path.isEmpty) return;
      state = restored.copyWith(
        error: 'Запись прервалась, путь сохранён. Продолжите или опубликуйте.',
      );
      AppLog.add('RouteRecorder: черновик восстановлен, ${restored.path.length} точек');
    } catch (e) {
      AppLog.add('RouteRecorder: черновик не прочитался — $e');
    }
  }

  void addPhoto(String localPath) {
    final point = state.lastPoint;
    if (point == null) return;

    state = state.copyWith(
      photos: [
        ...state.photos,
        PendingRoutePhoto(
          localPath: localPath,
          latitude: point.latitude,
          longitude: point.longitude,
          takenAt: DateTime.now(),
        ),
      ],
    );
    _save();
  }

  void removePhoto(PendingRoutePhoto photo) {
    state = state.copyWith(
      photos: [
        for (final item in state.photos)
          if (item.localPath != photo.localPath) item,
      ],
    );
  }

  RouteDraft draft(String title) => RouteDraft(
    title: title,
    path: state.path,
    distanceMeters: state.distanceMeters,
    duration: state.elapsed,
    startedAt: state.startedAt ?? DateTime.now(),
    photos: state.photos,
  );

  Future<bool> _ensurePermission() async {
    try {
      // Понятия «служба геолокации» на вебе нет, и geolocator там на этот
      // вызов бросается исключением. Жёсткая проверка закрыла бы запись
      // маршрута в браузере — а это зеркало приложения, по которому смотрят
      // с айфона. Реальный сигнал всё равно даёт разрешение и сам поток точек.
      if (!kIsWeb && !await Geolocator.isLocationServiceEnabled()) {
        state = state.copyWith(
          status: RecordingStatus.denied,
          error: 'Геолокация выключена в настройках телефона',
        );
        return false;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        state = state.copyWith(
          status: RecordingStatus.denied,
          error: 'Без доступа к геопозиции маршрут не записать',
        );
        return false;
      }

      return true;
    } catch (e) {
      AppLog.add('RouteRecorder: проверка разрешений упала — $e');
      // Причина в тексте не для красоты: без неё отказ на устройстве
      // неотличим от отказа в браузере, и чинить нечего.
      state = state.copyWith(
        status: RecordingStatus.failed,
        error: 'Не удалось получить доступ к геопозиции: $e',
      );
      return false;
    }
  }

  Future<void> _seedFirstPoint() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(const Duration(seconds: 12));

      if (state.status != RecordingStatus.recording) return;
      state = state.copyWith(
        path: [RouteCoordinate(position.latitude, position.longitude)],
      );
    } catch (e) {
      // Не фатально: поток всё равно подписан, первая точка просто придёт
      // позже. Ронять запись из-за одного промаха нельзя.
      AppLog.add('RouteRecorder: первая точка не пришла — $e');
    }
  }

  void _listenToPositions() {
    _positions?.cancel();
    // На Android поток держит служба переднего плана: запись идёт, когда
    // приложение свёрнуто или открыта другая вкладка.
    final settings = !kIsWeb && defaultTargetPlatform == TargetPlatform.android
        ? AndroidSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 5,
            foregroundNotificationConfig: const ForegroundNotificationConfig(
              notificationTitle: 'ChaWo: идёт запись маршрута',
              notificationText: 'Остановить или сохранить — на экране маршрута.',
              notificationChannelName: 'Запись маршрута',
              enableWakeLock: true,
              setOngoing: true,
            ),
          )
        : const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5);
    _positions =
        Geolocator.getPositionStream(locationSettings: settings).listen(
          _onPosition,
          onError: _onStreamError,
        );
  }

  /// Обрыв потока — не повод терять прогулку.
  ///
  /// Сигнал пропадает в арке, в подземном переходе, в лифте. Если уже есть
  /// точки, запись продолжается: показываем предупреждение и переподписываемся.
  /// Сносим всё только когда терять нечего.
  void _onStreamError(Object error) {
    AppLog.add('RouteRecorder: поток координат упал — $error');

    if (state.path.isEmpty) {
      _teardown();
      state = state.copyWith(
        status: RecordingStatus.failed,
        error: 'Сигнал GPS потерян: $error',
      );
      return;
    }

    state = state.copyWith(error: 'Сигнал GPS пропал, ищем заново');

    // Переподписка с паузой: ошибка обычно приходит сразу же, и подписка
    // «в лоб» превратилась бы в горячий цикл.
    _resubscribe?.cancel();
    _resubscribe = Timer(const Duration(seconds: 3), () {
      if (state.status == RecordingStatus.recording) _listenToPositions();
    });
  }

  void _onPosition(Position position) {
    if (state.status != RecordingStatus.recording) return;

    final now = DateTime.now();
    final previous = state.lastPoint;

    if (previous == null) {
      _lastSampleAt = now;
      state = state.copyWith(
        path: [RouteCoordinate(position.latitude, position.longitude)],
      );
      return;
    }

    final moved = Geolocator.distanceBetween(
      previous.latitude,
      previous.longitude,
      position.latitude,
      position.longitude,
    );

    if (moved < _minDistanceMeters) return;

    final seconds = now.difference(_lastSampleAt ?? now).inMilliseconds / 1000;
    if (seconds > 0 && moved / seconds > _maxSpeedMetersPerSecond) {
      AppLog.add('RouteRecorder: выброс на ${moved.round()} м отброшен');
      return;
    }

    _lastSampleAt = now;
    state = state.copyWith(
      path: [...state.path, RouteCoordinate(position.latitude, position.longitude)],
      distanceMeters: state.distanceMeters + moved.round(),
    );
    _save();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final startedAt = state.startedAt;
      if (startedAt == null) return;
      state = state.copyWith(elapsed: state.elapsed + const Duration(seconds: 1));
      final limit = state.limit;
      if (limit != null && state.elapsed >= limit) {
        stop();
        state = state.copyWith(
          error: 'Время записи вышло (${routeLimitLabel(limit)}). '
              'Опубликуйте маршрут или продолжите запись.',
        );
        AppLog.add('RouteRecorder: остановлено по лимиту ${routeLimitLabel(limit)}');
      }
    });
  }

  void _teardown() {
    _positions?.cancel();
    _positions = null;
    _ticker?.cancel();
    _ticker = null;
    _resubscribe?.cancel();
    _resubscribe = null;
  }
}

final routeRecorderProvider =
    NotifierProvider<RouteRecorder, RouteRecordingState>(RouteRecorder.new);
