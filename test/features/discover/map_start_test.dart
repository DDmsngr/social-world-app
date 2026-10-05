import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/features/discover/domain/activity.dart';
import 'package:social_world/features/discover/presentation/providers/map_start.dart';

void main() {
  ActivityCell cell(double lat, double score) =>
      ActivityCell(latitude: lat, longitude: 39.7, score: score, radiusMeters: 300);

  group('hottestZone', () {
    test('берёт зону с наибольшей оценкой', () {
      final target = hottestZone([cell(43.1, 0.3), cell(43.2, 0.9), cell(43.3, 0.5)]);
      expect(target?.latitude, 43.2);
    });

    test('пусто или всё почти нулевое — null, карта остаётся на городе', () {
      expect(hottestZone(const []), isNull);
      expect(hottestZone([cell(43.1, 0.01)]), isNull);
    });
  });
}
