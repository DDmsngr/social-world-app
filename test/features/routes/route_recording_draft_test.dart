import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/features/routes/domain/entities/city_route.dart';
import 'package:social_world/features/routes/presentation/providers/route_recorder.dart';

void main() {
  test('черновик прогулки переживает сохранение и восстанавливается на паузе', () {
    final state = RouteRecordingState(
      status: RecordingStatus.recording,
      path: const [RouteCoordinate(43.58, 39.72), RouteCoordinate(43.59, 39.73)],
      photos: [
        PendingRoutePhoto(
          localPath: '/tmp/a.jpg',
          latitude: 43.59,
          longitude: 39.73,
          takenAt: DateTime.utc(2026, 10, 8, 12),
        ),
      ],
      distanceMeters: 1350,
      startedAt: DateTime.utc(2026, 10, 8, 11, 30),
      elapsed: const Duration(minutes: 31, seconds: 5),
      limit: const Duration(hours: 1),
    );

    final restored = RouteRecordingState.fromJson(state.toJson());

    expect(restored.status, RecordingStatus.paused);
    expect(restored.path.length, 2);
    expect(restored.path.last.latitude, 43.59);
    expect(restored.photos.single.localPath, '/tmp/a.jpg');
    expect(restored.distanceMeters, 1350);
    expect(restored.elapsed, const Duration(minutes: 31, seconds: 5));
    expect(restored.startedAt, DateTime.utc(2026, 10, 8, 11, 30));
    // После перезапуска ограничение снято: запись продолжают вручную.
    expect(restored.limit, isNull);
  });

  test('подписи ограничения по времени', () {
    expect(routeLimitLabel(null), 'Без ограничения');
    expect(routeLimitLabel(const Duration(minutes: 30)), '30 мин');
    expect(routeLimitLabel(const Duration(hours: 2)), '2 ч');
    expect(routeLimitOptions.length, 5);
  });

  test('copyWith снимает лимит по флагу и сохраняет без него', () {
    const state = RouteRecordingState(limit: Duration(hours: 1));
    expect(state.copyWith().limit, const Duration(hours: 1));
    expect(state.copyWith(clearLimit: true).limit, isNull);
  });
}
