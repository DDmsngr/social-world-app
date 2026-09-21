import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/features/discover/domain/entities/city.dart';

void main() {
  test('неизвестный или пустой id даёт пилотный город', () {
    expect(Cities.parse(null), Cities.sochi);
    expect(Cities.parse('atlantis'), Cities.sochi);
    expect(Cities.parse('moscow').name, 'Москва');
  });

  test('поиск без запроса отдаёт весь список, с запросом — совпадения', () {
    expect(Cities.search('   '), Cities.all);
    expect(Cities.search('сОч').single, Cities.sochi);
    expect(Cities.search('нижний').single.id, 'nnovgorod');
    expect(Cities.search('атлантида'), isEmpty);
  });

  test('ближайший город считается от точки, а не берётся первым из списка', () {
    // Петербург: именно там Pulse показывал пустую карту, когда центр брали
    // с устройства.
    expect(Cities.nearestTo(59.96, 30.46).id, 'spb');
    expect(Cities.nearestTo(43.41, 39.92).id, 'sochi');
  });

  test('пилотная зона одна и это Сочи', () {
    expect(Cities.all.where((c) => c.isPilot).single, Cities.sochi);
    expect(Cities.fallback, Cities.sochi);
  });

  test('id уникальны — иначе выбор города сохранится не тем', () {
    final ids = Cities.all.map((c) => c.id).toSet();
    expect(ids.length, Cities.all.length);
  });
}
