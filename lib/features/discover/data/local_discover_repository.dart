import '../../../core/location/geo_privacy.dart';
import '../domain/activity.dart';
import '../domain/entities/discover_snapshot.dart';
import '../domain/entities/nearby_person.dart';
import '../domain/entities/place.dart';
import '../domain/repositories/discover_repository.dart';

class LocalDiscoverRepository implements DiscoverRepository {
  /// [activitySource] отдаёт события и моменты, которые лежат в соседних
  /// репозиториях-заглушках: без сервера считать активность больше не из чего.
  LocalDiscoverRepository({this.activitySource});

  final List<ActivityObject> Function()? activitySource;

  @override
  Future<Place?> loadPlace(String placeId) async {
    for (final place in _places) {
      if (place.id == placeId) return place;
    }
    return null;
  }

  @override
  Future<List<ActivityCell>> loadActivity(ActivityQuery query) async {
    final objects = [
      for (final place in _places)
        ActivityObject(
          kind: ActivityKind.place,
          latitude: place.latitude,
          longitude: place.longitude,
          category: place.category,
        ),
      ...?activitySource?.call(),
    ];
    return ActivityCalculator.compute(objects, query);
  }
  @override
  Future<DiscoverSnapshot> loadNearby({
    required double centerLatitude,
    required double centerLongitude,
    int radiusMeters = 3000,
  }) async {
    final people = _people
        .map((person) {
          // Мок повторяет боевой контракт: наружу отдаём только центр размытой зоны.
          final blurred = GeoPrivacy.blur(
            latitude: person.latitude,
            longitude: person.longitude,
            salt: person.id,
            radiusMeters: person.blurRadiusMeters,
          );
          return NearbyPerson(
            id: person.id,
            displayName: person.displayName,
            blurredLatitude: blurred.latitude,
            blurredLongitude: blurred.longitude,
            blurRadiusMeters: blurred.radiusMeters,
          );
        })
        .toList(growable: false);

    return DiscoverSnapshot(
      centerLatitude: centerLatitude,
      centerLongitude: centerLongitude,
      places: _places,
      people: people,
    );
  }

  /// На заглушках публиковать некуда: список людей и так захардкожен.
  @override
  Future<void> publishPresence({
    required double blurredLatitude,
    required double blurredLongitude,
    required int blurRadiusMeters,
  }) async {}

  @override
  Future<void> clearPresence() async {}

  static const _places = <Place>[
    Place(
      id: 'theatre-square',
      title: 'Театральная площадь',
      description: 'Открытое городское пространство у Зимнего театра.',
      category: 'Прогулка',
      latitude: 43.5789,
      longitude: 39.7232,
    ),
    Place(
      id: 'winter-theatre',
      title: 'Зимний театр',
      description: 'Спектакли, концерты и встречи в центре Сочи.',
      category: 'Культура',
      latitude: 43.5689,
      longitude: 39.7258,
    ),
    Place(
      id: 'art-square',
      title: 'Площадь Искусств',
      description: 'Музеи, зелёные аллеи и спокойный городской ритм.',
      category: 'Искусство',
      latitude: 43.5752,
      longitude: 39.7246,
    ),
    Place(
      id: 'seaside-promenade',
      title: 'Приморская набережная',
      description: 'Море, прогулки и вечерние встречи.',
      category: 'Набережная',
      latitude: 43.5740,
      longitude: 39.7289,
    ),
  ];

  static const _people = <_LocalPerson>[
    _LocalPerson('person-1', 'Алина', 43.5794, 39.7240, 500),
    _LocalPerson('person-2', 'Марк', 43.5778, 39.7219, 500),
    _LocalPerson('person-3', 'Саша', 43.5767, 39.7251, 1000),
    _LocalPerson('person-4', 'Лена', 43.5811, 39.7208, 500),
    _LocalPerson('person-5', 'Илья', 43.5749, 39.7272, 200),
    _LocalPerson('person-6', 'Ника', 43.5820, 39.7261, 1000),
  ];
}

class _LocalPerson {
  const _LocalPerson(
    this.id,
    this.displayName,
    this.latitude,
    this.longitude,
    this.blurRadiusMeters,
  );

  final String id;
  final String displayName;
  final double latitude;
  final double longitude;
  final double blurRadiusMeters;
}
