/// Метка на карте маршрута. Отдельный тип, потому что метки приходят из двух
/// разных источников: ещё не загруженные фото во время записи и уже
/// опубликованные — у них разные сущности, а карте нужна только точка.
class RouteMapMarker {
  const RouteMapMarker({
    required this.latitude,
    required this.longitude,
    this.label,
  });

  final double latitude;
  final double longitude;
  final String? label;
}
