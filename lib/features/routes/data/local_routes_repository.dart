import '../domain/entities/city_route.dart';
import '../domain/repositories/routes_repository.dart';

/// Маршруты на моках, пока бэкенд не подключён. Фото никуда не грузятся —
/// в карточке остаётся локальный путь к файлу, его хватает, чтобы пройти
/// сценарий целиком и посмотреть, как всё выглядит.
class LocalRoutesRepository implements RoutesRepository {
  LocalRoutesRepository({
    required this.currentUserId,
    required this.currentUserName,
  });

  final String Function() currentUserId;
  final String Function() currentUserName;

  final _routes = <String, CityRoute>{};
  var _nextId = 0;

  @override
  Future<CityRoute> publishRoute(RouteDraft draft) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));

    final id = 'local-route-${_nextId++}';
    final route = CityRoute(
      id: id,
      authorId: currentUserId(),
      authorName: currentUserName(),
      title: draft.title.trim(),
      path: draft.path,
      distanceMeters: draft.distanceMeters,
      duration: draft.duration,
      startedAt: draft.startedAt,
      createdAt: DateTime.now(),
      photos: [
        for (final (index, photo) in draft.photos.indexed)
          RoutePhoto(
            id: '$id-photo-$index',
            photoUrl: photo.localPath,
            latitude: photo.latitude,
            longitude: photo.longitude,
            takenAt: photo.takenAt,
          ),
      ],
    );

    _routes[id] = route;
    return route;
  }

  @override
  Future<CityRoute> loadRoute(String routeId) async {
    final route = _routes[routeId];
    if (route == null) throw Exception('Маршрут не найден');
    return route;
  }

  @override
  Future<void> deleteRoute(String routeId) async {
    _routes.remove(routeId);
  }
}
