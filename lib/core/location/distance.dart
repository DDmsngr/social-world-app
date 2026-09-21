import 'dart:math' as math;

/// Расстояние по поверхности между двумя точками, метры (формула гаверсинусов).
/// Для «сколько идти до события» точности с запасом: ошибка модели Земли —
/// доли процента.
double distanceMeters(double lat1, double lng1, double lat2, double lng2) {
  const earthRadius = 6371000.0;
  double rad(double deg) => deg * math.pi / 180;

  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final a =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * earthRadius * math.asin(math.min(1, math.sqrt(a)));
}

/// «350 м», «1,2 км», «14 км».
String formatDistance(double meters) {
  if (meters < 950) return '${(meters / 10).round() * 10} м';
  final km = meters / 1000;
  return km < 10
      ? '${km.toStringAsFixed(1).replaceAll('.', ',')} км'
      : '${km.round()} км';
}
