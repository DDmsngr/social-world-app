import '../entities/city_route.dart';

abstract interface class RoutesRepository {
  /// Загружает фото, сохраняет маршрут и публикует его в ленту одним действием.
  Future<CityRoute> publishRoute(RouteDraft draft);

  Future<CityRoute> loadRoute(String routeId);

  Future<void> deleteRoute(String routeId);
}
