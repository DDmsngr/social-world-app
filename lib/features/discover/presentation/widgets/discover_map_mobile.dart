import 'dart:io';

import 'package:flutter/material.dart';
import 'package:yandex_maps_mapkit/mapkit.dart' as ymk;
import 'package:yandex_maps_mapkit/mapkit_factory.dart';
import 'package:yandex_maps_mapkit/yandex_map.dart';

import '../../../../core/config/mapkit_boot.dart';
import '../../../../core/debug/app_log.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/sw_widgets.dart';
import '../../domain/entities/discover_snapshot.dart';
import '../../domain/entities/place.dart';

class DiscoverMap extends StatefulWidget {
  const DiscoverMap({
    super.key,
    required this.data,
    required this.places,
    required this.onPlaceTap,
  });

  final DiscoverSnapshot data;
  final List<Place> places;
  final ValueChanged<Place> onPlaceTap;

  @override
  State<DiscoverMap> createState() => _DiscoverMapState();
}

class _DiscoverMapState extends State<DiscoverMap> {
  late final AppLifecycleListener _lifecycle;
  ymk.MapObjectCollection? _objects;

  // Слушатели тапов живут ровно столько же, сколько метки: MapKit держит
  // на них слабую ссылку, и без своего списка они собираются сборщиком,
  // а метки молча перестают нажиматься.
  final _tapListeners = <_PlaceTapListener>[];

  bool _mapkitRunning = false;

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
    if (widget.data != old.data || widget.places != old.places) {
      _rebuildObjects();
    }
  }

  @override
  void dispose() {
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
    window.map.nightModeEnabled = true;
    _objects = window.map.mapObjects.addCollection();

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
          const ymk.TextStyle(
            size: 11,
            color: AppColors.text,
            outlineColor: AppColors.ink,
            placement: ymk.TextStylePlacement.Bottom,
            offset: 8,
          ),
        )
        ..addTapListener(listener);
    }
  }

  @override
  Widget build(BuildContext context) {
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
