import 'package:flutter/material.dart';

import '../../domain/entities/city_route.dart';
import 'route_map_marker.dart';
import 'route_sketch.dart';

/// Веб-версия карты маршрута.
///
/// MapKit на вебе не собирается, но путь — это ломаная, её силуэт читается и
/// без тайлов. Для зеркала приложения, по которому смотрят с айфона, это
/// лучше, чем заглушка «откройте на Android».
class RouteMap extends StatelessWidget {
  const RouteMap({
    super.key,
    required this.path,
    this.markers = const [],
    this.followLast = false,
  });

  final List<RouteCoordinate> path;
  final List<RouteMapMarker> markers;
  final bool followLast;

  @override
  Widget build(BuildContext context) =>
      RouteSketch(path: path, markers: markers);
}
