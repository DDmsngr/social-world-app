import '../entities/discover_snapshot.dart';

abstract interface class DiscoverRepository {
  Future<DiscoverSnapshot> loadNearby({
    required double centerLatitude,
    required double centerLongitude,
    int radiusMeters = 3000,
  });
}
