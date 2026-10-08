import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/city_route.dart';
import 'route_map_marker.dart';

/// Куда и в каком масштабе смотреть, чтобы весь путь влез в рамку.
///
/// Считается в проекции Web Mercator, как у обычных плиток: тогда линия и
/// подложка совпадают пиксель в пиксель. Вынесено отдельно от виджета, чтобы
/// проверяться тестом без экрана.
class RouteTileView {
  RouteTileView._({
    required this.zoom,
    required this.left,
    required this.top,
    required this.size,
  });

  /// Дробный масштаб: на нём считаются пиксели мира (256 * 2^zoom).
  final double zoom;

  /// Мировые пиксели левого верхнего угла рамки.
  final double left;
  final double top;
  final Size size;

  static const maxZoom = 17.0;
  static const _tile = 256.0;

  /// Положение точки в долях мира: x и y от 0 до 1.
  static Offset unit(double latitude, double longitude) {
    final lat = latitude.clamp(-85.05, 85.05) * math.pi / 180;
    final x = (longitude + 180) / 360;
    final y = (1 - math.log(math.tan(lat) + 1 / math.cos(lat)) / math.pi) / 2;
    return Offset(x, y);
  }

  static RouteTileView fit(
    List<RouteCoordinate> points,
    Size size, {
    double padding = 18,
  }) {
    final units = [for (final p in points) unit(p.latitude, p.longitude)];
    var minX = units.first.dx, maxX = units.first.dx;
    var minY = units.first.dy, maxY = units.first.dy;
    for (final u in units) {
      minX = math.min(minX, u.dx);
      maxX = math.max(maxX, u.dx);
      minY = math.min(minY, u.dy);
      maxY = math.max(maxY, u.dy);
    }

    final boxW = math.max(size.width - padding * 2, 1.0);
    final boxH = math.max(size.height - padding * 2, 1.0);
    final spanX = math.max(maxX - minX, 1e-9);
    final spanY = math.max(maxY - minY, 1e-9);
    // Масштаб, при котором охват пути ровно заполняет рамку. Прямая улица
    // вырождена по одной оси — её ограничивает maxZoom, а не деление на ноль.
    final zoom = math
        .min(
          math.log(boxW / (_tile * spanX)) / math.ln2,
          math.log(boxH / (_tile * spanY)) / math.ln2,
        )
        .clamp(1.0, maxZoom);

    final world = _tile * math.pow(2, zoom);
    final centerX = (minX + maxX) / 2 * world;
    final centerY = (minY + maxY) / 2 * world;
    return RouteTileView._(
      zoom: zoom,
      left: centerX - size.width / 2,
      top: centerY - size.height / 2,
      size: size,
    );
  }

  double get _world => _tile * math.pow(2, zoom).toDouble();

  /// Точка на экране в пикселях рамки.
  Offset project(double latitude, double longitude) {
    final u = unit(latitude, longitude);
    return Offset(u.dx * _world - left, u.dy * _world - top);
  }

  /// Плитки, которые попадают в рамку: z/x/y и положение на экране.
  List<({int z, int x, int y, Rect rect})> tiles() {
    final z = zoom.floor();
    final count = 1 << z;
    final tileSize = _tile * math.pow(2, zoom - z).toDouble();
    final firstX = (left / tileSize).floor();
    final lastX = ((left + size.width) / tileSize).floor();
    final firstY = math.max((top / tileSize).floor(), 0);
    final lastY = math.min(((top + size.height) / tileSize).floor(), count - 1);
    return [
      for (var ty = firstY; ty <= lastY; ty++)
        for (var tx = firstX; tx <= lastX; tx++)
          (
            z: z,
            x: tx % count < 0 ? tx % count + count : tx % count,
            y: ty,
            rect: Rect.fromLTWH(
              tx * tileSize - left,
              ty * tileSize - top,
              tileSize,
              tileSize,
            ),
          ),
    ];
  }
}

/// Карточка маршрута для ленты: линия поверх плиток OpenStreetMap.
///
/// Живая карта в каждой карточке убила бы скролл, а статичные карты Яндекса
/// ключ MapKit не отдаёт, поэтому плитки идут обычными картинками с кэшем.
/// Пока плитки не пришли (или нет сети), под линией остаётся фон темы.
class RouteTilePreview extends StatelessWidget {
  const RouteTilePreview({
    super.key,
    required this.path,
    this.markers = const [],
    this.padding = 18,
  });

  final List<RouteCoordinate> path;
  final List<RouteMapMarker> markers;
  final double padding;

  static const _tileUrl = 'https://tile.openstreetmap.org';

  @override
  Widget build(BuildContext context) {
    if (path.length < 2) {
      return ColoredBox(color: AppColors.ink);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        if (!size.isFinite || size.isEmpty) return const SizedBox.shrink();
        final view = RouteTileView.fit(path, size, padding: padding);
        final dark = AppColors.current.isDark;

        return ClipRect(
          child: ColoredBox(
            color: AppColors.ink,
            child: Stack(
              children: [
                for (final tile in view.tiles())
                  Positioned.fromRect(
                    rect: tile.rect,
                    child: CachedNetworkImage(
                      imageUrl: '$_tileUrl/${tile.z}/${tile.x}/${tile.y}.png',
                      httpHeaders: const {'User-Agent': 'ChaWo/1.0 (route preview)'},
                      fit: BoxFit.fill,
                      fadeInDuration: const Duration(milliseconds: 120),
                      errorWidget: (_, _, _) => const SizedBox.shrink(),
                      // В тёмной теме светлая карта режет глаза: инвертируем и
                      // притушаем, цвета уже не важны — важна читаемость улиц.
                      imageBuilder: (_, image) => ColorFiltered(
                        colorFilter: dark ? _darken : _soften,
                        child: Image(image: image, fit: BoxFit.fill),
                      ),
                    ),
                  ),
                Positioned.fill(
                  child: CustomPaint(
                    painter: _TileRoutePainter(view, path, markers),
                  ),
                ),
                Positioned(
                  right: 6,
                  top: 4,
                  child: Text(
                    '© OpenStreetMap',
                    style: TextStyle(
                      fontSize: 9,
                      color: AppColors.textDim.withValues(alpha: 0.8),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static const _darken = ColorFilter.matrix(<double>[
    -0.55, 0, 0, 0, 255 * 0.62,
    0, -0.55, 0, 0, 255 * 0.62,
    0, 0, -0.55, 0, 255 * 0.64,
    0, 0, 0, 1, 0,
  ]);

  static const _soften = ColorFilter.matrix(<double>[
    0.9, 0, 0, 0, 12,
    0, 0.9, 0, 0, 12,
    0, 0, 0.9, 0, 12,
    0, 0, 0, 1, 0,
  ]);
}

class _TileRoutePainter extends CustomPainter {
  _TileRoutePainter(this.view, this.path, this.markers);

  final RouteTileView view;
  final List<RouteCoordinate> path;
  final List<RouteMapMarker> markers;

  @override
  void paint(Canvas canvas, Size size) {
    final first = view.project(path.first.latitude, path.first.longitude);
    final line = Path()..moveTo(first.dx, first.dy);
    for (final point in path.skip(1)) {
      final o = view.project(point.latitude, point.longitude);
      line.lineTo(o.dx, o.dy);
    }
    // Подложка пёстрая, поэтому линию обводим: иначе она теряется на дорогах.
    canvas.drawPath(
      line,
      Paint()
        ..color = AppColors.ink.withValues(alpha: 0.85)
        ..strokeWidth = 7
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = AppColors.primary
        ..strokeWidth = 4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final last = view.project(path.last.latitude, path.last.longitude);
    for (final (point, color) in [(first, AppColors.geo), (last, AppColors.primary)]) {
      canvas.drawCircle(point, 7, Paint()..color = AppColors.ink);
      canvas.drawCircle(point, 5, Paint()..color = color);
    }

    for (final marker in markers) {
      final o = view.project(marker.latitude, marker.longitude);
      canvas.drawCircle(o, 6.5, Paint()..color = AppColors.paper);
      canvas.drawCircle(
        o,
        6.5,
        Paint()
          ..color = AppColors.primary
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );
    }
  }

  @override
  bool shouldRepaint(_TileRoutePainter old) =>
      old.view != view || old.path != path || old.markers != markers;
}
