/// Точка маршрута события. Порядок точек — порядок в списке; отдельного поля
/// «номер» нет, чтобы перестановка не требовала пересчёта.
class EventRoutePoint {
  const EventRoutePoint({
    required this.latitude,
    required this.longitude,
    this.title,
  });

  final double latitude;
  final double longitude;

  /// Адрес или название, как ввёл организатор. У точки, поставленной прямо на
  /// карте, названия может не быть.
  final String? title;

  EventRoutePoint copyWith({String? title}) => EventRoutePoint(
    latitude: latitude,
    longitude: longitude,
    title: title ?? this.title,
  );

  Map<String, dynamic> toJson() => {
    'lat': latitude,
    'lng': longitude,
    if (title?.trim() case final text? when text.isNotEmpty) 'title': text,
  };

  /// `null`, если запись битая: маршрут из базы не должен ронять карточку.
  static EventRoutePoint? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final lat = raw['lat'];
    final lng = raw['lng'];
    if (lat is! num || lng is! num) return null;
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
    final title = raw['title'];
    return EventRoutePoint(
      latitude: lat.toDouble(),
      longitude: lng.toDouble(),
      title: title is String ? title : null,
    );
  }

  static List<EventRoutePoint> parseList(dynamic raw) => raw is List
      ? [for (final item in raw) ?tryParse(item)]
      : const [];
}

/// Во сколько точек ограничен маршрут (совпадает с check в базе).
const maxEventRoutePoints = 25;
