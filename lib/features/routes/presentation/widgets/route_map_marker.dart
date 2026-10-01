/// Метка на карте маршрута. Отдельный тип, потому что метки приходят из двух
/// разных источников: ещё не загруженные фото во время записи и уже
/// опубликованные — у них разные сущности, а карте нужна только точка.
class RouteMapMarker {
  const RouteMapMarker({
    required this.latitude,
    required this.longitude,
    this.label,
    this.photoUrl,
  });

  final double latitude;
  final double longitude;
  final String? label;

  /// Если задан, метка рисуется круглым превью этого фото (ссылка или путь к
  /// файлу), а не точкой.
  final String? photoUrl;
}
