import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:yandex_maps_mapkit/mapkit.dart' as ymk;
import 'package:yandex_maps_mapkit/mapkit_factory.dart';
import 'package:yandex_maps_mapkit/yandex_map.dart';

import '../../../../core/config/mapkit_boot.dart';
import '../../../../core/debug/app_log.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/sw_widgets.dart';
import '../../../events/domain/entities/event.dart';
import '../../domain/entities/discover_snapshot.dart';
import '../../domain/entities/place.dart';

class DiscoverMap extends StatefulWidget {
  const DiscoverMap({
    super.key,
    required this.data,
    required this.places,
    required this.onPlaceTap,
    this.events = const [],
    this.onEventTap,
    this.filterActive = false,
  });

  final DiscoverSnapshot data;
  final List<Place> places;
  final ValueChanged<Place> onPlaceTap;

  /// Только события с координатами места — остальные на карту не попадают.
  final List<Event> events;
  final ValueChanged<Event>? onEventTap;

  /// true, пока в поиске есть непустой текст — тогда камера подстраивается
  /// под найденные места вместо того, чтобы держать исходный центр района.
  /// Без этого фильтр молча убирал метки за пределами экрана, а человек видел
  /// «поиск ничего не делает».
  final bool filterActive;

  @override
  State<DiscoverMap> createState() => _DiscoverMapState();
}

class _DiscoverMapState extends State<DiscoverMap> {
  late final AppLifecycleListener _lifecycle;
  ymk.MapObjectCollection? _objects;
  ymk.MapWindow? _window;
  ymk.UserLocationLayer? _userLocationLayer;
  bool _locatingSelf = false;

  // Слушатели тапов живут ровно столько же, сколько метки: MapKit держит
  // на них слабую ссылку, и без своего списка они собираются сборщиком,
  // а метки молча перестают нажиматься.
  final _tapListeners = <_PlaceTapListener>[];

  bool _mapkitRunning = false;
  AppPalette? _appliedPalette;

  @override
  void initState() {
    super.initState();
    _startMapkit();
    _lifecycle = AppLifecycleListener(
      onResume: _startMapkit,
      onInactive: _stopMapkit,
    );
  }

  @override
  void didUpdateWidget(DiscoverMap old) {
    super.didUpdateWidget(old);
    if (widget.data != old.data ||
        widget.places != old.places ||
        widget.events != old.events) {
      _rebuildObjects();
    }

    final searchJustStarted = widget.filterActive && !old.filterActive;
    final searchResultsChanged = widget.filterActive && widget.places != old.places;
    if ((searchJustStarted || searchResultsChanged) && widget.places.isNotEmpty) {
      _focusOnPlaces(widget.places);
    } else if (!widget.filterActive && old.filterActive) {
      _resetCamera();
    }
  }

  @override
  void dispose() {
    // Явно гасим видимость перед уходом виджета: поле — единственная сильная
    // ссылка на объект слоя, и без явного использования его считают мёртвым
    // кодом, хотя MapKit держит его живым, пока виден слой геолокации.
    _userLocationLayer?.setVisible(false);
    _stopMapkit();
    _lifecycle.dispose();
    super.dispose();
  }

  void _startMapkit() {
    if (_mapkitRunning) return;
    _mapkitRunning = true;
    mapkit.onStart();
    AppLog.add('DiscoverMap: mapkit.onStart()');
  }

  void _stopMapkit() {
    if (!_mapkitRunning) return;
    _mapkitRunning = false;
    mapkit.onStop();
    AppLog.add('DiscoverMap: mapkit.onStop()');
  }

  void _onMapCreated(ymk.MapWindow window) {
    AppLog.add(
      'DiscoverMap: onMapCreated, центр ${widget.data.centerLatitude},'
      ' ${widget.data.centerLongitude}',
    );
    _appliedPalette = AppColors.current;
    window.map.nightModeEnabled = AppColors.current.isDark;
    _window = window;
    _objects = window.map.mapObjects.addCollection();

    // Штатный слой MapKit: синяя точка + окружность точности сама следит за
    // сервисом геолокации, свою метку рисовать не нужно.
    _userLocationLayer = mapkit.createUserLocationLayer(window)
      ..setVisible(true)
      ..setDefaultSource();

    window.map.move(
      ymk.CameraPosition(
        ymk.Point(
          latitude: widget.data.centerLatitude,
          longitude: widget.data.centerLongitude,
        ),
        zoom: 14.5,
        azimuth: 0,
        tilt: 0,
      ),
    );

    _rebuildObjects();
  }

  void _focusOnPlaces(List<Place> places) {
    final window = _window;
    if (window == null) return;

    var minLat = places.first.latitude;
    var maxLat = places.first.latitude;
    var minLng = places.first.longitude;
    var maxLng = places.first.longitude;
    for (final place in places) {
      minLat = minLat < place.latitude ? minLat : place.latitude;
      maxLat = maxLat > place.latitude ? maxLat : place.latitude;
      minLng = minLng < place.longitude ? minLng : place.longitude;
      maxLng = maxLng > place.longitude ? maxLng : place.longitude;
    }

    // Один результат — не прямоугольник, а точка: обычный zoom вместо
    // cameraPositionForGeometry, у которой на вырожденном боксе выходит
    // максимальное приближение.
    if (places.length == 1) {
      window.map.move(
        ymk.CameraPosition(
          ymk.Point(latitude: minLat, longitude: minLng),
          zoom: 16,
          azimuth: 0,
          tilt: 0,
        ),
        animation: const ymk.Animation(type: ymk.AnimationType.Smooth, duration: 0.4),
      );
      return;
    }

    final position = window.map.cameraPositionForGeometry(
      ymk.Geometry.fromBoundingBox(
        ymk.BoundingBox(
          ymk.Point(latitude: minLat, longitude: minLng),
          ymk.Point(latitude: maxLat, longitude: maxLng),
        ),
      ),
    );
    window.map.move(
      position,
      animation: const ymk.Animation(type: ymk.AnimationType.Smooth, duration: 0.4),
    );
  }

  void _resetCamera() {
    final window = _window;
    if (window == null) return;
    window.map.move(
      ymk.CameraPosition(
        ymk.Point(
          latitude: widget.data.centerLatitude,
          longitude: widget.data.centerLongitude,
        ),
        zoom: 14.5,
        azimuth: 0,
        tilt: 0,
      ),
      animation: const ymk.Animation(type: ymk.AnimationType.Smooth, duration: 0.4),
    );
  }

  Future<void> _recenterOnMe() async {
    if (_locatingSelf) return;
    setState(() => _locatingSelf = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        AppLog.add('DiscoverMap: службы геолокации выключены на устройстве');
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        AppLog.add('DiscoverMap: нет разрешения на геолокацию');
        return;
      }

      final position = await Geolocator.getCurrentPosition();
      _window?.map.move(
        ymk.CameraPosition(
          ymk.Point(latitude: position.latitude, longitude: position.longitude),
          zoom: 15.5,
          azimuth: 0,
          tilt: 0,
        ),
        animation: const ymk.Animation(
          type: ymk.AnimationType.Smooth,
          duration: 0.4,
        ),
      );
    } catch (error) {
      AppLog.add('DiscoverMap: не удалось определить местоположение: $error');
    } finally {
      if (mounted) setState(() => _locatingSelf = false);
    }
  }

  void _rebuildObjects() {
    final collection = _objects;
    if (collection == null) return;

    collection.clear();
    _tapListeners.clear();

    final center = ymk.Point(
      latitude: widget.data.centerLatitude,
      longitude: widget.data.centerLongitude,
    );

    collection.addCircle(
        ymk.Circle(center, radius: 280 + widget.data.people.length * 55),
      )
      ..strokeColor = AppColors.primary.withValues(alpha: 0.55)
      ..strokeWidth = 2
      ..fillColor = AppColors.primary.withValues(
        alpha: 0.035 + widget.data.pulseLevel * 0.025,
      );

    for (final person in widget.data.people) {
      // Зоны людей — холодным geo: бордовый на карте занят пульсом района,
      // и если красить им же метки, они читаются как кнопки.
      collection.addCircle(
          ymk.Circle(
            ymk.Point(
              latitude: person.blurredLatitude,
              longitude: person.blurredLongitude,
            ),
            radius: person.blurRadiusMeters,
          ),
        )
        ..strokeColor = AppColors.geo.withValues(alpha: 0.7)
        ..strokeWidth = 1.5
        ..fillColor = AppColors.geo.withValues(alpha: 0.18);
    }

    for (final place in widget.places) {
      final listener = _PlaceTapListener(() => widget.onPlaceTap(place));
      _tapListeners.add(listener);

      collection
          .addPlacemarkWithPoint(
            ymk.Point(latitude: place.latitude, longitude: place.longitude),
          )
        ..setText(place.title)
        ..setTextStyle(
          ymk.TextStyle(
            size: 11,
            color: AppColors.text,
            outlineColor: AppColors.ink,
            placement: ymk.TextStylePlacement.Bottom,
            offset: 8,
          ),
        )
        ..addTapListener(listener);
    }

    // События подписаны временем и акцентным цветом — так они с первого
    // взгляда отличаются от обычных мест, даже если стоят в той же точке.
    final onEventTap = widget.onEventTap;
    for (final event in widget.events) {
      if (!event.hasLocation) continue;
      final listener = _PlaceTapListener(() => onEventTap?.call(event));
      _tapListeners.add(listener);

      collection
          .addPlacemarkWithPoint(
            ymk.Point(latitude: event.latitude!, longitude: event.longitude!),
          )
        ..setText('${_hhmm(event.startsAt)} · ${event.title}')
        ..setTextStyle(
          ymk.TextStyle(
            size: 12,
            color: AppColors.primaryTint,
            outlineColor: AppColors.ink,
            placement: ymk.TextStylePlacement.Top,
            offset: 8,
          ),
        )
        ..addTapListener(listener);
    }
  }

  static String _hhmm(DateTime moment) {
    final local = moment.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  // Метки красятся цветами темы в момент создания — после смены темы их
  // надо перерисовать, а саму карту перевести в дневной/ночной режим.
  void _followTheme() {
    if (_window == null || identical(_appliedPalette, AppColors.current)) {
      return;
    }
    _appliedPalette = AppColors.current;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _window?.map.nightModeEnabled = AppColors.current.isDark;
      _rebuildObjects();
    });
  }

  @override
  Widget build(BuildContext context) {
    _followTheme();
    if (!Platform.isAndroid && !Platform.isIOS) {
      return const _MobileMapUnavailable(
        title: 'Карта доступна на Android и iOS',
        text: 'Откройте этот раздел в мобильном приложении.',
      );
    }
    if (!MapkitBoot.isReady) {
      return _MobileMapUnavailable(
        title: 'Карта не запустилась',
        text: MapkitBoot.status == 'no_key'
            ? 'Добавьте YANDEX_MAPKIT_API_KEY в .env и перезапустите приложение.'
            : 'MapKit не инициализировался: ${MapkitBoot.status}',
      );
    }

    return Stack(
      children: [
        YandexMap(
          onMapCreated: _onMapCreated,
          platformViewType: PlatformViewType.Hybrid,
        ),
        // Пока тайлы не гарантированно грузятся (см. заметку в
        // mapkit_boot_native.dart) — виден статус и префикс ключа, чтобы не
        // гадать вслепую при следующем баг-репорте с телефона. DevMode тут
        // не подходит: он гаснет ровно тогда, когда бэкенд настоящий — то
        // есть в каждой боевой сборке. Убрать после того, как тайлы точно
        // заработают на устройстве.
        Positioned(
            left: 8,
            top: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'mapkit: ${MapkitBoot.status}',
                style: const TextStyle(color: Colors.white, fontSize: 10),
              ),
            ),
          ),
        Positioned(
          right: 16,
          bottom: 108,
          child: Semantics(
            button: true,
            label: _locatingSelf
                ? 'Определяем местоположение'
                : 'Показать моё местоположение',
            child: Tooltip(
              message: 'Моё местоположение',
              child: Material(
                color: AppColors.ink2,
                shape: const CircleBorder(),
                elevation: 4,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _recenterOnMe,
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: _locatingSelf
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(Icons.my_location, color: AppColors.primaryTint),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PlaceTapListener extends ymk.MapObjectTapListener {
  _PlaceTapListener(this.onTap);

  final VoidCallback onTap;

  @override
  bool onMapObjectTap(ymk.MapObject mapObject, ymk.Point point) {
    onTap();
    return true;
  }
}

class _MobileMapUnavailable extends StatelessWidget {
  const _MobileMapUnavailable({required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: GlassCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel('Карта'),
              const SizedBox(height: 12),
              Text(title, style: AppTypography.serif(28)),
              const SizedBox(height: 8),
              Text(text, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ),
    );
  }
}
