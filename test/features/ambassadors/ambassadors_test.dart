import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/features/ambassadors/ambassadors_screen.dart';

void main() {
  test('шапка разбирает ответ ambassador_overview', () {
    final o = AmbassadorOverview.fromJson({
      'me': null,
      'city': null,
      'year': 2026,
      'season': {'id': 1, 'ends_at': '2026-12-14T21:00:00+00:00', 'starts_at': '2026-10-15T21:00:00+00:00'},
      'leaders': [
        {
          'city': 'Санкт-Петербург',
          'name': 'Артур Сергеев',
          'total_ap': 1,
          'username': 'archi',
          'season_ap': 1,
          'avatar_url': null,
          'profile_id': '7860f83d-7b5f-4676-b932-ecd46d912ad3',
          'prize_eligible': false,
        },
      ],
      'prize_min_ap': 20000,
      'prizes_enabled': true,
    });
    expect(o.seasonEnds!.toUtc(), DateTime.utc(2026, 12, 14, 21));
    expect(o.myPlace, isNull);
    expect(o.leaders.single.city, 'Санкт-Петербург');
    expect(o.leaders.single.row.name, 'Артур Сергеев');
    expect(o.leaders.single.row.points, 1);
    expect(o.leaders.single.eligible, isFalse);
  });

  test('строка рейтинга без имени не падает', () {
    final r = RatingRow.fromMap({'place': 2, 'profile_id': 'x', 'year_ap': 15, 'total_ap': 20}, 'year_ap');
    expect(r.name, 'Без имени');
    expect(r.points, 15);
  });

  test('Зал славы различает врио', () {
    final e = HallEntry.fromMap({
      'kind': 'ambassador',
      'profile_id': 'x',
      'name': 'Аня',
      'city': 'Сочи',
      'role': 'acting',
      'ends_at': '2026-12-14T21:00:00+00:00',
      'active': true,
    });
    expect(e.role, 'acting');
    expect(e.active, isTrue);
  });
}
