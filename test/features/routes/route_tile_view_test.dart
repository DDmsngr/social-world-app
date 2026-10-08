import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/features/routes/domain/entities/city_route.dart';
import 'package:social_world/features/routes/presentation/widgets/route_tile_preview.dart';

void main() {
  const size = Size(360, 190);
  const walk = [
    RouteCoordinate(43.5855, 39.7231),
    RouteCoordinate(43.5902, 39.7298),
    RouteCoordinate(43.5961, 39.7255),
    RouteCoordinate(43.6010, 39.7340),
  ];

  test('весь путь помещается в рамку с отступом', () {
    final view = RouteTileView.fit(walk, size, padding: 18);
    for (final p in walk) {
      final o = view.project(p.latitude, p.longitude);
      expect(o.dx, inInclusiveRange(17, size.width - 17));
      expect(o.dy, inInclusiveRange(17, size.height - 17));
    }
  });

  test('плитки покрывают рамку без дыр', () {
    final view = RouteTileView.fit(walk, size);
    final tiles = view.tiles();
    expect(tiles, isNotEmpty);
    var covered = Rect.fromLTWH(
      tiles.first.rect.left,
      tiles.first.rect.top,
      0,
      0,
    );
    for (final t in tiles) {
      covered = covered.expandToInclude(t.rect);
    }
    expect(covered.left, lessThanOrEqualTo(0));
    expect(covered.top, lessThanOrEqualTo(0));
    expect(covered.right, greaterThanOrEqualTo(size.width));
    expect(covered.bottom, greaterThanOrEqualTo(size.height));
    final count = 1 << tiles.first.z;
    for (final t in tiles) {
      expect(t.x, inInclusiveRange(0, count - 1));
      expect(t.y, inInclusiveRange(0, count - 1));
    }
  });

  test('прямая улица и стоячая точка не ломают масштаб', () {
    const straight = [
      RouteCoordinate(43.5855, 39.7231),
      RouteCoordinate(43.5955, 39.7231),
    ];
    const still = [
      RouteCoordinate(43.5855, 39.7231),
      RouteCoordinate(43.5855, 39.7231),
    ];
    for (final path in [straight, still]) {
      final view = RouteTileView.fit(path, size);
      expect(view.zoom, lessThanOrEqualTo(RouteTileView.maxZoom));
      expect(view.zoom.isFinite, isTrue);
      expect(view.tiles(), isNotEmpty);
    }
  });
}

