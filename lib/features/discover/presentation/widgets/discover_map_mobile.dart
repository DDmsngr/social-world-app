import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:yandex_maps_mapkit/mapkit.dart' as ymk;
import 'package:yandex_maps_mapkit/mapkit_factory.dart';
import 'package:yandex_maps_mapkit/yandex_map.dart';

import '../../../../core/config/mapkit_boot.dart';
import '../../../../core/debug/app_log.dart';
import '../../../../core/location/device_position.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/sw_widgets.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../events/domain/entities/event.dart';
import '../../../needs/domain/entities/need_request.dart';
import '../../../quests/domain/entities/quest.dart';
import '../../domain/activity.dart';
import '../../domain/entities/discover_snapshot.dart';
import '../../domain/entities/nearby_person.dart';
import '../../domain/entities/place.dart';
import '../providers/discover_providers.dart';
import 'activity_palette.dart';
import 'map_types.dart';

class DiscoverMap extends StatefulWidget {
  const DiscoverMap({
    super.key,
    required this.data,
    required this.places,
    required this.onPlaceTap,
    this.events = const [],
    this.people = const [],
    this.quests = const [],
    this.needs = const [],
    this.onQuestTap,
    this.onNeedTap,
    this.activity = const [],
    this.activityMode = ActivityMode.lively,
    this.anchor,
    this.focus,
    this.onEventTap,
    this.onPersonTap,
    this.onLongTap,
    this.filterActive = false,
  });

  final DiscoverSnapshot data;
  final List<Place> places;
  final ValueChanged<Place> onPlaceTap;

  /// Только события с координатами места — остальные на карту не попадают.
  final List<Event> events;
  final List<NearbyPerson> people;
  final ValueChanged<Event>? onEventTap;
  final ValueChanged<NearbyPerson>? onPersonTap;

  /// Квесты — самые заметные метки Pulse (п. 41); просьбы «Мне надо» — в
  /// размытой точке, которую отдал сервер.
  final List<Quest> quests;
  final List<NeedRequest> needs;
  final ValueChanged<Quest>? onQuestTap;
  final ValueChanged<NeedRequest>? onNeedTap;

  /// Готовые зоны активности с сервера и режим, в котором их рисовать.
  final List<ActivityCell> activity;
  final ActivityMode activityMode;

  /// Точка сценария «Рядом» — рисуется кругом заданного радиуса.
  final NearbyAnchor? anchor;

  /// Запрос «наведи камеру сюда» (выбранный результат поиска). Новый запрос —
  /// новый объект: по нему виджет отличает повтор от прежнего.
  final MapFocus? focus;

  /// Долгое нажатие на карте: ставит точку «Рядом», когда включён выбор.
  final void Function(double latitude, double longitude)? onLongTap;

  /// true, пока действует поиск или фильтр — тогда камера подстраивается
  /// под то, что осталось на карте, вместо того, чтобы держать исходный центр.
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

  // Слушатели тапов живут ровно столько же, сколько метки: MapKit держит
  // на них слабую ссылку, и без своего списка они собираются сборщиком,
  // а метки молча перестают нажиматься.
  final _tapListeners = <_TapListener>[];
  final _inputListener = _InputListener();

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
    _inputListener.onLongTap = (lat, lng) => widget.onLongTap?.call(lat, lng);
  }

  @override
  void didUpdateWidget(DiscoverMap old) {
    super.didUpdateWidget(old);

    final objectsChanged =
        widget.data != old.data ||
        !identical(widget.places, old.places) ||
        !identical(widget.events, old.events) ||
        !identical(widget.people, old.people) ||
        !identical(widget.quests, old.quests) ||
        !identical(widget.needs, old.needs) ||
        !identical(widget.activity, old.activity) ||
        widget.activityMode != old.activityMode ||
        widget.anchor != old.anchor;
    if (objectsChanged) _rebuildObjects();

    // Точка «Рядом» поставлена или сдвинута — камера идёт к ней, даже если
    // в радиусе ничего нет и подгонять «по найденному» не к чему.
    if (widget.anchor != null && !identical(widget.anchor, old.anchor)) {
      _resetCamera();
      return;
    }

    // Сменился город — камера обязана переехать, иначе человек выбирает
    // другой город и продолжает смотреть на прежний.
    if (widget.data.centerLatitude != old.data.centerLatitude ||
        widget.data.centerLongitude != old.data.centerLongitude) {
      _resetCamera();
      return;
    }

    final focus = widget.focus;
    if (focus != null && !identical(focus, old.focus)) {
      _moveTo(focus.latitude, focus.longitude, zoom: focus.zoom);
      return;
    }

    final shownChanged =
        !identical(widget.places, old.places) ||
        !identical(widget.events, old.events) ||
        !identical(widget.people, old.people) ||
        !identical(widget.quests, old.quests) ||
        !identical(widget.needs, old.needs);
    final searchJustStarted = widget.filterActive && !old.filterActive;
    if ((searchJustStarted || (widget.filterActive && shownChanged))) {
      _fitShown();
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
    window.map.addInputListener(_inputListener);

    _resetCamera(animated: false);
    _rebuildObjects();
    _enableUserLocationLayer(window);
  }

  /// Штатный слой MapKit: синяя точка + окружность точности. Включаем его
  /// только с выданным разрешением: без него нативная часть Яндекса каждые
  /// десять секунд сыпала в лог `SecurityException: uid … does not have
  /// ACCESS_COARSE_LOCATION`, а толку от слоя всё равно не было. Карта
  /// маршрутов этот слой не создаёт вовсе — и работает без нареканий.
  Future<void> _enableUserLocationLayer(ymk.MapWindow window) async {
    if (!await hasLocationPermission()) return;
    if (!mounted || _window != window) return;
    _userLocationLayer = mapkit.createUserLocationLayer(window)
      ..setVisible(true)
      ..setDefaultSource();
  }

  void _moveTo(double latitude, double longitude, {double zoom = 16}) {
    _window?.map.move(
      ymk.CameraPosition(
        ymk.Point(latitude: latitude, longitude: longitude),
        zoom: zoom,
        azimuth: 0,
        tilt: 0,
      ),
      animation: const ymk.Animation(
        type: ymk.AnimationType.Smooth,
        duration: 0.4,
      ),
    );
  }

  /// Камера охватывает всё, что осталось на карте после фильтра или поиска.
  void _fitShown() {
    final window = _window;
    if (window == null) return;

    final points = <(double, double)>[
      for (final place in widget.places) (place.latitude, place.longitude),
      for (final event in widget.events)
        if (event.hasLocation) (event.latitude!, event.longitude!),
      for (final person in widget.people)
        (person.blurredLatitude, person.blurredLongitude),
      for (final quest in widget.quests)
        if (quest.hasLocation) (quest.latitude!, quest.longitude!),
      for (final need in widget.needs)
        if (need.hasLocation) (need.latitude!, need.longitude!),
    ];
    if (points.isEmpty) return;

    var minLat = points.first.$1;
    var maxLat = points.first.$1;
    var minLng = points.first.$2;
    var maxLng = points.first.$2;
    for (final (lat, lng) in points) {
      minLat = minLat < lat ? minLat : lat;
      maxLat = maxLat > lat ? maxLat : lat;
      minLng = minLng < lng ? minLng : lng;
      maxLng = maxLng > lng ? maxLng : lng;
    }

    // Один результат — не прямоугольник, а точка: обычный zoom вместо
    // cameraPositionForGeometry, у которой на вырожденном боксе выходит
    // максимальное приближение.
    if (points.length == 1 ||
        (maxLat - minLat < 1e-5 && maxLng - minLng < 1e-5)) {
      _moveTo(minLat, minLng);
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
      animation: const ymk.Animation(
        type: ymk.AnimationType.Smooth,
        duration: 0.4,
      ),
    );
  }

  void _resetCamera({bool animated = true}) {
    final window = _window;
    if (window == null) return;
    final anchor = widget.anchor;
    window.map.move(
      ymk.CameraPosition(
        ymk.Point(
          latitude: anchor?.latitude ?? widget.data.centerLatitude,
          longitude: anchor?.longitude ?? widget.data.centerLongitude,
        ),
        zoom: anchor == null ? 14.5 : _zoomForRadius(anchor.radiusMeters),
        azimuth: 0,
        tilt: 0,
      ),
      animation: animated
          ? const ymk.Animation(type: ymk.AnimationType.Smooth, duration: 0.4)
          : null,
    );
  }

  /// Подбирает масштаб так, чтобы круг «Рядом» помещался на экране.
  double _zoomForRadius(int meters) {
    if (meters <= 500) return 15.6;
    if (meters <= 1000) return 14.7;
    if (meters <= 3000) return 13.3;
    return 12.3;
  }

  void _rebuildObjects() {
    final collection = _objects;
    if (collection == null) return;

    collection.clear();
    _tapListeners.clear();

    // Слой активности — самый нижний: мягкие полупрозрачные зоны без обводки.
    _drawActivity(collection);

    final anchor = widget.anchor;
    if (anchor != null) {
      final center = ymk.Point(
        latitude: anchor.latitude,
        longitude: anchor.longitude,
      );
      // Синий — только геолокация и люди: точка «Рядом» это геолокация.
      collection.addCircle(
          ymk.Circle(center, radius: anchor.radiusMeters.toDouble()),
        )
        ..strokeColor = AppColors.geo.withValues(alpha: 0.85)
        ..strokeWidth = 1.5
        ..fillColor = AppColors.geo.withValues(alpha: 0.06)
        ..zIndex = 1;
      collection.addPlacemarkWithPoint(center)
        ..setText(anchor.isDevice ? 'Вы здесь' : 'Точка поиска')
        ..setTextStyle(
          ymk.TextStyle(
            size: 11,
            color: AppColors.geo,
            outlineColor: AppColors.ink,
            placement: ymk.TextStylePlacement.Bottom,
            offset: 8,
          ),
        )
        ..zIndex = 2;
    }

    for (final person in widget.people) {
      // Зоны людей — холодным geo: бордовый на карте занят активностью,
      // и если красить им же метки, они читаются как кнопки.
      final listener = _TapListener(() => widget.onPersonTap?.call(person));
      _tapListeners.add(listener);
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
        ..fillColor = AppColors.geo.withValues(alpha: 0.18)
        ..zIndex = 3
        ..addTapListener(listener);
    }

    for (final place in widget.places) {
      final listener = _TapListener(() => widget.onPlaceTap(place));
      _tapListeners.add(listener);

      collection.addPlacemarkWithPoint(
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
        ..zIndex = 4
        ..addTapListener(listener);
    }

    // События подписаны временем и акцентным цветом — так они с первого
    // взгляда отличаются от обычных мест, даже если стоят в той же точке.
    final onEventTap = widget.onEventTap;
    for (final event in widget.events) {
      if (!event.hasLocation) continue;
      final listener = _TapListener(() => onEventTap?.call(event));
      _tapListeners.add(listener);

      collection.addPlacemarkWithPoint(
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
        ..zIndex = 5
        ..addTapListener(listener);
    }

    // Просьба «Мне надо» — неяркая подпись: она про человека, а не про
    // событие, и не должна перекрикивать квесты.
    final onNeedTap = widget.onNeedTap;
    for (final need in widget.needs) {
      if (!need.hasLocation) continue;
      final listener = _TapListener(() => onNeedTap?.call(need));
      _tapListeners.add(listener);

      collection.addPlacemarkWithPoint(
          ymk.Point(latitude: need.latitude!, longitude: need.longitude!),
        )
        ..setText('Мне надо: ${_short(need.text, 28)}')
        ..setTextStyle(
          ymk.TextStyle(
            size: 11,
            color: AppColors.geo,
            outlineColor: AppColors.ink,
            placement: ymk.TextStylePlacement.Bottom,
            offset: 8,
          ),
        )
        ..zIndex = 6
        ..addTapListener(listener);
    }

    // Квест — главный объект Pulse: подпись крупнее, со счётчиком мест.
    // Завершённый квест (след на сутки, п. 42) — тусклее и без счётчика.
    final onQuestTap = widget.onQuestTap;
    for (final quest in widget.quests) {
      if (!quest.hasLocation) continue;
      final listener = _TapListener(() => onQuestTap?.call(quest));
      _tapListeners.add(listener);

      collection.addPlacemarkWithPoint(
          ymk.Point(latitude: quest.latitude!, longitude: quest.longitude!),
        )
        ..setText(
          quest.isTrail
              ? _short(quest.title, 30)
              : '${_short(quest.title, 30)} · ${quest.occupancy}',
        )
        ..setTextStyle(
          ymk.TextStyle(
            size: quest.isTrail ? 11 : 13,
            color: quest.isTrail ? AppColors.textDim : AppColors.primaryTint,
            outlineColor: AppColors.ink,
            placement: ymk.TextStylePlacement.Top,
            offset: 8,
          ),
        )
        ..zIndex = 7
        ..addTapListener(listener);
    }
  }

  static String _short(String text, int max) =>
      text.length <= max ? text : '${text.substring(0, max - 1).trimRight()}…';

  /// Зона рисуется тремя вложенными кругами разной плотности — получается
  /// мягкое пятно без резкой границы. Цвет — по шкале активности Pulse
  /// (зелёный → красный), в режиме «спокойнее» шкала не применяется.
  void _drawActivity(ymk.MapObjectCollection collection) {
    final isDark = AppColors.current.isDark;

    for (final cell in widget.activity) {
      final intensity = cell.intensityFor(widget.activityMode);
      if (intensity <= 0.04) continue;

      final tone = ActivityPalette.forCell(intensity, widget.activityMode);
      final base = activityAlpha(intensity, isDark: isDark);
      final radius = cell.radiusMeters * 0.85;
      final center = ymk.Point(
        latitude: cell.latitude,
        longitude: cell.longitude,
      );

      for (final (scale, alpha) in const [
        (1.35, 0.35),
        (0.95, 0.55),
        (0.55, 0.8),
      ]) {
        collection.addCircle(ymk.Circle(center, radius: radius * scale))
          ..strokeColor = Colors.transparent
          ..strokeWidth = 0
          ..fillColor = tone.withValues(alpha: base * alpha)
          ..zIndex = 0;
      }
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
    // Ровно то же, что и на рабочей карте маршрутов (route_map_mobile.dart):
    // из build() возвращается голый YandexMap, без собственного Stack и без
    // виджетов поверх платформенного слоя. Кнопка «моё местоположение»
    // переехала в discover_screen.dart, к остальным элементам поверх карты.
    return YandexMap(
      onMapCreated: _onMapCreated,
      platformViewType: PlatformViewType.Hybrid,
    );
  }
}

class _TapListener extends ymk.MapObjectTapListener {
  _TapListener(this.onTap);

  final VoidCallback onTap;

  @override
  bool onMapObjectTap(ymk.MapObject mapObject, ymk.Point point) {
    onTap();
    return true;
  }
}

class _InputListener implements ymk.MapInputListener {
  void Function(double latitude, double longitude)? onLongTap;

  @override
  void onMapTap(ymk.Map map, ymk.Point point) {}

  @override
  void onMapLongTap(ymk.Map map, ymk.Point point) =>
      onLongTap?.call(point.latitude, point.longitude);
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
