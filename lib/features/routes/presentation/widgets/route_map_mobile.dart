import 'dart:io';

import 'package:flutter/material.dart';
import 'package:yandex_maps_mapkit/mapkit.dart' as ymk;
import 'package:yandex_maps_mapkit/mapkit_factory.dart';
import 'package:yandex_maps_mapkit/yandex_map.dart';

import '../../../../core/config/mapkit_boot.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/city_route.dart';
import 'route_map_marker.dart';

class RouteMap extends StatefulWidget {
  const RouteMap({
    super.key,
    required this.path,
    this.markers = const [],
    this.followLast = false,
  });

  final List<RouteCoordinate> path;
  final List<RouteMapMarker> markers;

  /// Во время записи камера едет за последней точкой; у готового маршрута
  /// вместо этого один раз подбирается охват всего пути.
  final bool followLast;

  @override
  State<RouteMap> createState() => _RouteMapState();
}

class _RouteMapState extends State<RouteMap> {
  late final AppLifecycleListener _lifecycle;
  ymk.MapWindow? _window;
  ymk.MapObjectCollection? _objects;
  bool _mapkitRunning = false;
  bool _framedOnce = false;

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
  void didUpdateWidget(RouteMap old) {
    super.didUpdateWidget(old);
    if (widget.path.length != old.path.length ||
        widget.markers.length != old.markers.length) {
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
  }

  void _stopMapkit() {
    if (!_mapkitRunning) return;
    _mapkitRunning = false;
    mapkit.onStop();
  }

  void _onMapCreated(ymk.MapWindow window) {
    _window = window;
    window.map.nightModeEnabled = true;
    _objects = window.map.mapObjects.addCollection();
    _rebuildObjects();
  }

  void _rebuildObjects() {
    final collection = _objects;
    final window = _window;
    if (collection == null || window == null) return;

    collection.clear();

    final points = [
      for (final point in widget.path)
        ymk.Point(latitude: point.latitude, longitude: point.longitude),
    ];

    if (points.length >= 2) {
      collection.addPolylineWithGeometry(ymk.Polyline(points))
        ..style = const ymk.LineStyle(
          strokeWidth: 4,
          outlineWidth: 1,
          outlineColor: AppColors.ink,
        )
        ..setStrokeColor(AppColors.primaryTint);

      collection.addPlacemarkWithPoint(points.first)
        ..setText('старт')
        ..setTextStyle(_textStyle(AppColors.geo));

      if (!widget.followLast) {
        collection.addPlacemarkWithPoint(points.last)
          ..setText('финиш')
          ..setTextStyle(_textStyle(AppColors.primaryTint));
      }
    }

    for (final marker in widget.markers) {
      final placemark = collection.addPlacemarkWithPoint(
        ymk.Point(latitude: marker.latitude, longitude: marker.longitude),
      );
      if (marker.label != null) {
        placemark
          ..setText(marker.label!)
          ..setTextStyle(_textStyle(AppColors.text));
      }
    }

    _moveCamera(window, points);
  }

  void _moveCamera(ymk.MapWindow window, List<ymk.Point> points) {
    if (points.isEmpty) return;

    if (widget.followLast) {
      window.map.move(
        ymk.CameraPosition(points.last, zoom: 16.5, azimuth: 0, tilt: 0),
      );
      return;
    }

    // Охват всего пути подбираем один раз: иначе при каждой перерисовке камера
    // дёргается обратно, стоит пользователю отвести карту рукой.
    if (_framedOnce) return;
    _framedOnce = true;

    if (points.length < 2) {
      window.map.move(
        ymk.CameraPosition(points.first, zoom: 16, azimuth: 0, tilt: 0),
      );
      return;
    }

    final position = window.map.cameraPositionForGeometry(
      ymk.Geometry.fromPolyline(ymk.Polyline(points)),
    );
    // Чуть отъезжаем: вплотную подогнанный охват обрезает метки по краям.
    window.map.move(
      ymk.CameraPosition(
        position.target,
        zoom: position.zoom - 0.4,
        azimuth: position.azimuth,
        tilt: position.tilt,
      ),
    );
  }

  ymk.TextStyle _textStyle(Color color) => ymk.TextStyle(
    size: 11,
    color: color,
    outlineColor: AppColors.ink,
    placement: ymk.TextStylePlacement.Bottom,
    offset: 8,
  );

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return const ColoredBox(
        color: AppColors.ink,
        child: Center(
          child: Text(
            'Карта доступна на Android и iOS',
            style: TextStyle(color: AppColors.textDim, fontSize: 13),
          ),
        ),
      );
    }

    if (!MapkitBoot.isReady) {
      return ColoredBox(
        color: AppColors.ink,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              'Карта не запустилась: ${MapkitBoot.status}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textDim, fontSize: 13),
            ),
          ),
        ),
      );
    }

    return YandexMap(
      onMapCreated: _onMapCreated,
      platformViewType: PlatformViewType.Hybrid,
    );
  }
}
