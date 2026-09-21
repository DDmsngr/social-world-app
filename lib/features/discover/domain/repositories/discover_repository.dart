import '../activity.dart';
import '../entities/discover_snapshot.dart';
import '../entities/place.dart';

abstract interface class DiscoverRepository {
  Future<DiscoverSnapshot> loadNearby({
    required double centerLatitude,
    required double centerLongitude,
    int radiusMeters = 3000,
  });

  /// Место по id: ссылка или страница места могут вести за пределы уже
  /// загруженной выборки «рядом». `null` — такого места нет.
  Future<Place?> loadPlace(String placeId);

  /// Зоны активности под фильтры пользователя. Считает сервер (PostGIS,
  /// `city_activity`): клиент получает готовые ячейки и не тянет на телефон
  /// все объекты города.
  Future<List<ActivityCell>> loadActivity(ActivityQuery query);

  /// Кладёт в `locations` точку присутствия — уже размытую вызывающим кодом.
  /// Точные координаты сюда не попадают и устройство не покидают.
  Future<void> publishPresence({
    required double blurredLatitude,
    required double blurredLongitude,
    required int blurRadiusMeters,
  });

  /// Убирает точку целиком: «меня на карте нет». Не протухание через два часа,
  /// а немедленное исчезновение — для выключенного тумблера и выхода из аккаунта.
  Future<void> clearPresence();
}
