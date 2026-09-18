import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/city_route.dart';
import 'route_map_marker.dart';

/// Силуэт маршрута без карты.
///
/// Нужен в двух местах: в вебе, где MapKit не собирается, и в ленте, где
/// нативная карта в каждой карточке убила бы скролл — на экране их может быть
/// несколько сразу.
class RouteSketch extends StatelessWidget {
  const RouteSketch({
    super.key,
    required this.path,
    this.markers = const [],
    this.strokeWidth = 3,
    this.padding = 24,
  });

  final List<RouteCoordinate> path;
  final List<RouteMapMarker> markers;
  final double strokeWidth;
  final double padding;

  @override
  Widget build(BuildContext context) {
    if (path.length < 2) {
      return ColoredBox(
        color: AppColors.ink,
        child: Center(
          child: Text(
            'Путь ещё не записан',
            style: TextStyle(color: AppColors.textDim, fontSize: 13),
          ),
        ),
      );
    }

    return ColoredBox(
      color: AppColors.ink,
      child: CustomPaint(
        painter: _RoutePainter(
          path: path,
          markers: markers,
          strokeWidth: strokeWidth,
          padding: padding,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _RoutePainter extends CustomPainter {
  _RoutePainter({
    required this.path,
    required this.markers,
    required this.strokeWidth,
    required this.padding,
  });

  final List<RouteCoordinate> path;
  final List<RouteMapMarker> markers;
  final double strokeWidth;
  final double padding;

  @override
  void paint(Canvas canvas, Size size) {
    var minLat = path.first.latitude, maxLat = path.first.latitude;
    var minLng = path.first.longitude, maxLng = path.first.longitude;
    for (final point in path) {
      minLat = minLat < point.latitude ? minLat : point.latitude;
      maxLat = maxLat > point.latitude ? maxLat : point.latitude;
      minLng = minLng < point.longitude ? minLng : point.longitude;
      maxLng = maxLng > point.longitude ? maxLng : point.longitude;
    }

    // Трек по прямой улице вырожден по одной оси — без защиты это деление
    // на ноль и схлопывание в точку.
    final spanLat = (maxLat - minLat).abs() < 1e-9 ? 1e-9 : maxLat - minLat;
    final spanLng = (maxLng - minLng).abs() < 1e-9 ? 1e-9 : maxLng - minLng;

    final boxWidth = size.width - padding * 2;
    final boxHeight = size.height - padding * 2;
    if (boxWidth <= 0 || boxHeight <= 0) return;

    final scale = (boxWidth / spanLng) < (boxHeight / spanLat)
        ? boxWidth / spanLng
        : boxHeight / spanLat;

    final offsetX = padding + (boxWidth - spanLng * scale) / 2;
    final offsetY = padding + (boxHeight - spanLat * scale) / 2;

    Offset project(double latitude, double longitude) => Offset(
      offsetX + (longitude - minLng) * scale,
      // Широта растёт вверх, экранная ось Y — вниз.
      offsetY + (maxLat - latitude) * scale,
    );

    final start = project(path.first.latitude, path.first.longitude);
    final line = Path()..moveTo(start.dx, start.dy);
    for (final point in path.skip(1)) {
      final offset = project(point.latitude, point.longitude);
      line.lineTo(offset.dx, offset.dy);
    }

    canvas.drawPath(
      line,
      Paint()
        ..color = AppColors.primaryTint
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final finish = project(path.last.latitude, path.last.longitude);
    canvas.drawCircle(start, strokeWidth * 2, Paint()..color = AppColors.geo);
    canvas.drawCircle(finish, strokeWidth * 2, Paint()..color = AppColors.primary);

    for (final marker in markers) {
      final offset = project(marker.latitude, marker.longitude);
      canvas.drawCircle(offset, strokeWidth * 1.7, Paint()..color = AppColors.paper);
      canvas.drawCircle(
        offset,
        strokeWidth * 1.7,
        Paint()
          ..color = AppColors.primary
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );
    }
  }

  @override
  bool shouldRepaint(_RoutePainter old) =>
      old.path.length != path.length ||
      old.markers.length != markers.length ||
      old.strokeWidth != strokeWidth;
}
