import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/features/discover/data/local_discover_repository.dart';

void main() {
  const centerLatitude = 43.5789;
  const centerLongitude = 39.7232;

  group('LocalDiscoverRepository', () {
    test('возвращает места и размытые точки людей вокруг Сочи', () async {
      final data = await LocalDiscoverRepository().loadNearby(
        centerLatitude: centerLatitude,
        centerLongitude: centerLongitude,
      );

      expect(data.places, isNotEmpty);
      expect(data.people, hasLength(6));
      expect(data.pulseLevel, 2);
      expect(
        data.people.every((person) => person.blurRadiusMeters >= 200),
        isTrue,
      );

      final first = data.people.first;
      expect(first.blurredLatitude, isNot(43.5794));
      expect(first.blurredLongitude, isNot(39.7240));
    });

    test('размытие стабильно между загрузками', () async {
      final repository = LocalDiscoverRepository();
      final first = await repository.loadNearby(
        centerLatitude: centerLatitude,
        centerLongitude: centerLongitude,
      );
      final second = await repository.loadNearby(
        centerLatitude: centerLatitude,
        centerLongitude: centerLongitude,
      );

      expect(
        first.people.map((person) => person.blurredLatitude),
        orderedEquals(second.people.map((person) => person.blurredLatitude)),
      );
      expect(
        first.people.map((person) => person.blurredLongitude),
        orderedEquals(second.people.map((person) => person.blurredLongitude)),
      );
    });

    test('своя точка на карте становится местом с теми же координатами', () async {
      final place = await LocalDiscoverRepository().createCustomPlace(
        title: '  ',
        latitude: 43.6,
        longitude: 39.7,
      );

      expect(place.title, 'Точка на карте');
      expect(place.latitude, 43.6);
      expect(place.longitude, 39.7);
    });
  });
}