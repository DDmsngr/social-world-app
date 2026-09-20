import '../entities/discover_snapshot.dart';

abstract interface class DiscoverRepository {
  Future<DiscoverSnapshot> loadNearby({
    required double centerLatitude,
    required double centerLongitude,
    int radiusMeters = 3000,
  });

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
