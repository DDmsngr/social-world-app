import '../domain/entities/city_route.dart';

/// Перевод пути между форматом приложения и форматом PostGIS.
///
/// Вынесено отдельно и покрыто тестами не из любви к слоям: и в EWKT, и в
/// GeoJSON координаты идут в порядке «долгота, широта», а во всём остальном
/// приложении — «широта, долгота». Перепутать здесь местами два числа значит
/// увезти все маршруты в другую точку планеты, и никакой ошибки при этом не
/// возникнет — линия просто нарисуется не там.
abstract final class RouteGeometry {
  static String toEwktLineString(List<RouteCoordinate> path) {
    final points = path
        .map((point) => '${point.longitude} ${point.latitude}')
        .join(', ');
    return 'SRID=4326;LINESTRING($points)';
  }

  static String toEwktPoint(double latitude, double longitude) =>
      'SRID=4326;POINT($longitude $latitude)';

  static List<RouteCoordinate> fromGeoJson(dynamic geoJson) {
    if (geoJson is! Map) return const [];

    final coordinates = geoJson['coordinates'];
    if (coordinates is! List) return const [];

    return [
      for (final pair in coordinates)
        if (pair is List && pair.length >= 2 && pair[0] is num && pair[1] is num)
          RouteCoordinate(
            (pair[1] as num).toDouble(),
            (pair[0] as num).toDouble(),
          ),
    ];
  }
}
