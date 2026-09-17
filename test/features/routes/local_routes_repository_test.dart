import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/features/routes/data/local_routes_repository.dart';
import 'package:social_world/features/routes/domain/entities/city_route.dart';

void main() {
  LocalRoutesRepository build() => LocalRoutesRepository(
    currentUserId: () => 'me',
    currentUserName: () => 'Алексей',
  );

  RouteDraft draft({String title = 'Вечер у моря', int photos = 0}) => RouteDraft(
    title: title,
    path: const [
      RouteCoordinate(43.5789, 39.7232),
      RouteCoordinate(43.5801, 39.7250),
      RouteCoordinate(43.5812, 39.7269),
    ],
    distanceMeters: 420,
    duration: const Duration(minutes: 8),
    startedAt: DateTime(2026, 9, 17, 19, 30),
    photos: [
      for (var i = 0; i < photos; i++)
        PendingRoutePhoto(
          localPath: '/tmp/photo-$i.jpg',
          latitude: 43.579 + i * 0.001,
          longitude: 39.723 + i * 0.001,
          takenAt: DateTime(2026, 9, 17, 19, 32 + i),
        ),
    ],
  );

  group('LocalRoutesRepository', () {
    test('опубликованный маршрут читается обратно целиком', () async {
      final repository = build();
      final published = await repository.publishRoute(draft(photos: 2));
      final loaded = await repository.loadRoute(published.id);

      expect(loaded.title, 'Вечер у моря');
      expect(loaded.authorId, 'me');
      expect(loaded.authorName, 'Алексей');
      expect(loaded.path, hasLength(3));
      expect(loaded.distanceMeters, 420);
      expect(loaded.duration, const Duration(minutes: 8));
      expect(loaded.photos, hasLength(2));
    });

    test('фото сохраняют свою точку съёмки, а не начало маршрута', () async {
      final repository = build();
      final route = await repository.publishRoute(draft(photos: 2));

      expect(route.photos.first.latitude, closeTo(43.579, 1e-9));
      expect(route.photos.last.latitude, closeTo(43.580, 1e-9));
      expect(route.photos.first.photoUrl, '/tmp/photo-0.jpg');
    });

    test('каждая публикация получает свой id', () async {
      final repository = build();
      final first = await repository.publishRoute(draft(title: 'Первый'));
      final second = await repository.publishRoute(draft(title: 'Второй'));

      expect(first.id, isNot(second.id));
      expect((await repository.loadRoute(first.id)).title, 'Первый');
      expect((await repository.loadRoute(second.id)).title, 'Второй');
    });

    test('удалённый маршрут больше не открывается', () async {
      final repository = build();
      final route = await repository.publishRoute(draft());

      await repository.deleteRoute(route.id);

      expect(() => repository.loadRoute(route.id), throwsException);
    });
  });
}
