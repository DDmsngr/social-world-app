import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:yandex_maps_mapkit/image.dart' as ymi;
import 'package:yandex_maps_mapkit/mapkit.dart' as ymk;
import 'package:yandex_maps_mapkit/mapkit_factory.dart';
import 'package:yandex_maps_mapkit/yandex_map.dart';

import '../../../core/config/mapkit_boot.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../routes/presentation/widgets/route_photo_icon.dart';
import 'live_map_marker.dart';

/// Карта трансляции: аватарки людей, которые делятся геопозицией. Камера один
/// раз подбирает охват всех, дальше её двигает человек (или кнопка «показать
/// всех» на экране — через [frameKey]).
class LiveMap extends StatefulWidget {
  const LiveMap({super.key, required this.markers, this.frameKey = 0});

  final List<LiveMapMarker> markers;

  /// Меняется — камера заново охватывает всех.
  final int frameKey;

  @override
  State<LiveMap> createState() => _LiveMapState();
}

class _LiveMapState extends State<LiveMap> {
  late final AppLifecycleListener _lifecycle;
  ymk.MapWindow? _window;
  ymk.MapObjectCollection? _objects;
  bool _mapkitRunning = false;
  bool _framed = false;

  @override
  void initState() {
    super.initState();
    _startMapkit();
    _lifecycle = AppLifecycleListener(onResume: _startMapkit, onInactive: _stopMapkit);
  }

  @override
  void didUpdateWidget(LiveMap old) {
    super.didUpdateWidget(old);
    if (old.frameKey != widget.frameKey) _framed = false;
    _rebuild();
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
    window.map.nightModeEnabled = AppColors.current.isDark;
    _objects = window.map.mapObjects.addCollection();
    _rebuild();
  }

  void _rebuild() {
    final collection = _objects;
    final window = _window;
    if (collection == null || window == null) return;
    collection.clear();
    final points = <ymk.Point>[];
    for (final marker in widget.markers) {
      final point = ymk.Point(latitude: marker.latitude, longitude: marker.longitude);
      points.add(point);
      final placemark = collection.addPlacemarkWithPoint(point)
        ..setText(marker.label)
        ..setTextStyle(
          ymk.TextStyle(
            size: 11,
            color: marker.me ? AppColors.geo : AppColors.text,
            outlineColor: AppColors.ink,
            placement: ymk.TextStylePlacement.Bottom,
            offset: 10,
          ),
        );
      final url = marker.avatarUrl;
      if (url != null) {
        placemark
          ..setIcon(
            ymi.ImageProvider(() => renderPhotoMarkerIcon(imageProviderFor(url)), id: 'live-avatar:$url'),
          )
          ..setIconStyle(const ymk.IconStyle(anchor: math.Point(0.5, 0.5), scale: 0.5, zIndex: 10));
      }
    }
    if (_framed || points.isEmpty) return;
    _framed = true;
    if (points.length == 1) {
      window.map.move(ymk.CameraPosition(points.first, zoom: 15.5, azimuth: 0, tilt: 0));
      return;
    }
    final position = window.map.cameraPositionForGeometry(
      ymk.Geometry.fromPolyline(ymk.Polyline(points)),
    );
    window.map.move(
      ymk.CameraPosition(position.target, zoom: math.min(position.zoom - 0.6, 16), azimuth: 0, tilt: 0),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return ColoredBox(
        color: AppColors.ink,
        child: Center(child: Text('Карта доступна на Android и iOS', style: TextStyle(color: AppColors.textDim))),
      );
    }
    if (!MapkitBoot.isReady) {
      return ColoredBox(
        color: AppColors.ink,
        child: Center(
          child: Text('Карта не запустилась: ${MapkitBoot.status}', style: TextStyle(color: AppColors.textDim)),
        ),
      );
    }
    return YandexMap(onMapCreated: _onMapCreated, platformViewType: PlatformViewType.Hybrid);
  }
}
