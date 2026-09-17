/// Точка пути. Намеренно без времени: в базе маршрут лежит как linestring,
/// у которого поточечных отметок времени нет — они нужны только во время
/// записи и живут в [RouteDraft].
class RouteCoordinate {
  const RouteCoordinate(this.latitude, this.longitude);

  final double latitude;
  final double longitude;
}

class RoutePhoto {
  const RoutePhoto({
    required this.id,
    required this.photoUrl,
    required this.latitude,
    required this.longitude,
    required this.takenAt,
    this.caption,
  });

  final String id;
  final String photoUrl;
  final double latitude;
  final double longitude;
  final DateTime takenAt;
  final String? caption;
}

/// Опубликованный маршрут. Назван CityRoute, а не Route: Route уже занят
/// самим Flutter (material.dart), и коллизия имён в экранах неизбежна.
class CityRoute {
  const CityRoute({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.title,
    required this.path,
    required this.distanceMeters,
    required this.duration,
    required this.startedAt,
    required this.createdAt,
    this.authorAvatarUrl,
    this.photos = const [],
  });

  final String id;
  final String authorId;
  final String authorName;
  final String? authorAvatarUrl;
  final String title;
  final List<RouteCoordinate> path;
  final int distanceMeters;
  final Duration duration;
  final DateTime startedAt;
  final DateTime createdAt;
  final List<RoutePhoto> photos;
}

/// Короткая карточка для списков: путь здесь упрощён на стороне SQL, полную
/// геометрию прогулки в список тянуть незачем.
class RouteSummary {
  const RouteSummary({
    required this.id,
    required this.title,
    required this.preview,
    required this.distanceMeters,
    required this.duration,
    required this.createdAt,
    this.photoCount = 0,
  });

  final String id;
  final String title;
  final List<RouteCoordinate> preview;
  final int distanceMeters;
  final Duration duration;
  final DateTime createdAt;
  final int photoCount;
}

/// Фото, снятое во время записи и ещё не загруженное на сервер.
class PendingRoutePhoto {
  const PendingRoutePhoto({
    required this.localPath,
    required this.latitude,
    required this.longitude,
    required this.takenAt,
  });

  final String localPath;
  final double latitude;
  final double longitude;
  final DateTime takenAt;
}

/// То, что накопилось за прогулку и уходит на публикацию одним куском.
class RouteDraft {
  const RouteDraft({
    required this.title,
    required this.path,
    required this.distanceMeters,
    required this.duration,
    required this.startedAt,
    this.photos = const [],
  });

  final String title;
  final List<RouteCoordinate> path;
  final int distanceMeters;
  final Duration duration;
  final DateTime startedAt;
  final List<PendingRoutePhoto> photos;
}
