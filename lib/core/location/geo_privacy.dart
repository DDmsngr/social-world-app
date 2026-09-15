import 'dart:math' as math;

/// Размытие геопозиции.
///
/// Точные координаты пользователя не покидают устройство и никогда не пишутся
/// в базу — наружу уходит только точка, привязанная к центру ячейки сетки.
/// Это требование из плана (фаза 0) и одновременно снижение риска по 152-ФЗ:
/// чем грубее гео, тем меньше данных, которые придётся защищать и хранить в РФ.
///
/// Сетка сдвинута на соль, привязанную к пользователю, чтобы по публичным
/// точкам нельзя было восстановить общую решётку и вычислить, где проходят
/// границы ячеек.
abstract final class GeoPrivacy {
  /// Радиус по умолчанию — район, а не подъезд.
  static const double defaultRadiusMeters = 500;

  /// Что пользователь может выбрать в настройках приватности.
  static const List<double> radiusOptions = [200, 500, 1000, 3000];

  static const double _metersPerDegreeLat = 111320;

  static BlurredPoint blur({
    required double latitude,
    required double longitude,
    required String salt,
    double radiusMeters = defaultRadiusMeters,
  }) {
    final cellLat = radiusMeters / _metersPerDegreeLat;
    final cosLat = math.cos(latitude * math.pi / 180).abs();
    // У полюсов меридианы сходятся — не даём ячейке разъехаться до бесконечности.
    final cellLng = radiusMeters / (_metersPerDegreeLat * math.max(cosLat, 0.01));

    final offsetLat = _saltFraction(salt, 'lat');
    final offsetLng = _saltFraction(salt, 'lng');

    final snappedLat =
        _snap(latitude, cellLat, offsetLat).clamp(-90.0, 90.0).toDouble();
    final snappedLng = _wrapLongitude(_snap(longitude, cellLng, offsetLng));

    return BlurredPoint(
      latitude: snappedLat,
      longitude: snappedLng,
      radiusMeters: radiusMeters,
    );
  }

  /// Сдвигаем сетку на соль, округляем до ячейки, возвращаем центр ячейки.
  static double _snap(double value, double cell, double offsetFraction) {
    final shifted = value + offsetFraction * cell;
    final index = (shifted / cell).floor();
    return (index + 0.5) * cell - offsetFraction * cell;
  }

  static double _wrapLongitude(double lng) {
    var result = (lng + 180) % 360;
    if (result < 0) result += 360;
    return result - 180;
  }

  /// Стабильная дробь [0,1) из соли — без криптографии, задача не секретность,
  /// а невоспроизводимость сетки со стороны.
  static double _saltFraction(String salt, String axis) {
    var hash = 0x811c9dc5;
    for (final unit in '$salt:$axis'.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash / 0xFFFFFFFF;
  }
}

class BlurredPoint {
  const BlurredPoint({
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
  });

  final double latitude;
  final double longitude;
  final double radiusMeters;

  /// То, что уходит в `locations` — точных координат здесь нет по определению.
  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        'blur_radius_m': radiusMeters.round(),
      };

  @override
  String toString() =>
      'BlurredPoint($latitude, $longitude, ±${radiusMeters.round()}м)';
}
