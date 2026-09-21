import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/features/discover/domain/activity.dart';

ActivityQuery _q(DateTime at, {Set<MapLayer>? layers, Set<String> categories = const {}}) =>
    ActivityQuery(
      latitude: 43.58,
      longitude: 39.72,
      at: at,
      layers: layers ?? const {MapLayer.events, MapLayer.places, MapLayer.moments},
      categories: categories,
    );

ActivityObject _event(DateTime at, {int hours = 1, int people = 5}) => ActivityObject(
  kind: ActivityKind.event,
  latitude: 43.58,
  longitude: 39.72,
  participants: people,
  startsAt: at.add(Duration(hours: hours)),
);

void main() {
  final now = DateTime(2026, 9, 21, 18);

  test('скорое событие весит больше далёкого', () {
    const c = ActivityConfig.defaults;
    expect(
      ActivityCalculator.weightOf(_event(now, hours: 1), now, c),
      greaterThan(ActivityCalculator.weightOf(_event(now, hours: 8), now, c)),
    );
  });

  test('старое и слишком далёкое не входит в расчёт', () {
    const c = ActivityConfig.defaults;
    expect(ActivityCalculator.weightOf(_event(now, hours: 30), now, c), 0);
    expect(ActivityCalculator.weightOf(_event(now, hours: -10), now, c), 0);
    final oldMoment = ActivityObject(
      kind: ActivityKind.moment,
      latitude: 43.58,
      longitude: 39.72,
      createdAt: now.subtract(const Duration(hours: 48)),
    );
    expect(ActivityCalculator.weightOf(oldMoment, now, c), 0);
  });

  test('слои и категории режут объекты; пустой фильтр даёт пустой слой', () {
    final objects = [_event(now)];
    expect(ActivityCalculator.compute(objects, _q(now)), isNotEmpty);
    expect(
      ActivityCalculator.compute(objects, _q(now, layers: {MapLayer.places})),
      isEmpty,
    );
    expect(
      ActivityCalculator.compute(objects, _q(now, categories: {'Спорт'})),
      isEmpty,
    );
  });

  test('плотная зона сильнее одинокого места, оценка в 0..1', () {
    final crowd = [for (var i = 0; i < 4; i++) _event(now, people: 20)];
    final busy = ActivityCalculator.compute(crowd, _q(now)).first.score;
    final lonely = ActivityCalculator.compute([
      const ActivityObject(kind: ActivityKind.place, latitude: 43.58, longitude: 39.72),
    ], _q(now)).first.score;
    expect(busy, greaterThan(lonely));
    expect(busy, lessThanOrEqualTo(1));
    expect(lonely, lessThan(0.3));
  });

  test('«спокойнее» — те же ячейки, где есть место и мало жизни', () {
    final cells = ActivityCalculator.compute([
      const ActivityObject(kind: ActivityKind.place, latitude: 43.58, longitude: 39.72),
    ], _q(now));
    expect(cells.first.intensityFor(ActivityMode.calm), greaterThan(0));
    final crowd = ActivityCalculator.compute([
      for (var i = 0; i < 4; i++) _event(now, people: 20),
      const ActivityObject(kind: ActivityKind.place, latitude: 43.58, longitude: 39.72),
    ], _q(now));
    expect(crowd.first.intensityFor(ActivityMode.calm), 0);
  });
}