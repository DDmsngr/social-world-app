import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/features/routes/data/route_geometry.dart';
import 'package:social_world/features/routes/domain/entities/city_route.dart';

void main() {
  group('RouteGeometry', () {
    // Сочи: широта ~43, долгота ~39. Числа намеренно разные и оба валидные как
    // широта — если их переставить местами, тест это поймает, а «похожие»
    // координаты вроде 43/43 пропустили бы ошибку.
    const sochi = RouteCoordinate(43.5789, 39.7232);
    const nextPoint = RouteCoordinate(43.5801, 39.7250);

    test('в EWKT координаты идут в порядке «долгота широта»', () {
      final wkt = RouteGeometry.toEwktLineString([sochi, nextPoint]);

      expect(
        wkt,
        'SRID=4326;LINESTRING(39.7232 43.5789, 39.725 43.5801)',
      );
    });

    test('точка тоже пишется долготой вперёд', () {
      expect(
        RouteGeometry.toEwktPoint(sochi.latitude, sochi.longitude),
        'SRID=4326;POINT(39.7232 43.5789)',
      );
    });

    test('GeoJSON разбирается обратно без перестановки координат', () {
      final path = RouteGeometry.fromGeoJson({
        'type': 'LineString',
        'coordinates': [
          [39.7232, 43.5789],
          [39.7250, 43.5801],
        ],
      });

      expect(path, hasLength(2));
      expect(path.first.latitude, closeTo(43.5789, 1e-9));
      expect(path.first.longitude, closeTo(39.7232, 1e-9));
      expect(path.last.latitude, closeTo(43.5801, 1e-9));
    });

    test('путь переживает круг «в базу и обратно» без сдвига', () {
      final wkt = RouteGeometry.toEwktLineString([sochi, nextPoint]);
      // Так же, как это сделал бы PostGIS: st_asgeojson отдаёт [lng, lat].
      final coordinates = wkt
          .replaceAll('SRID=4326;LINESTRING(', '')
          .replaceAll(')', '')
          .split(', ')
          .map((pair) => pair.split(' ').map(double.parse).toList())
          .toList();

      final path = RouteGeometry.fromGeoJson({
        'type': 'LineString',
        'coordinates': coordinates,
      });

      expect(path.first.latitude, closeTo(sochi.latitude, 1e-9));
      expect(path.first.longitude, closeTo(sochi.longitude, 1e-9));
    });

    test('мусор вместо геометрии не роняет разбор', () {
      expect(RouteGeometry.fromGeoJson(null), isEmpty);
      expect(RouteGeometry.fromGeoJson('LINESTRING(1 2)'), isEmpty);
      expect(RouteGeometry.fromGeoJson({'type': 'LineString'}), isEmpty);
      expect(
        RouteGeometry.fromGeoJson({
          'coordinates': [
            [39.7],
            ['нет', 'чисел'],
            [39.7232, 43.5789],
          ],
        }),
        hasLength(1),
      );
    });
  });
}
