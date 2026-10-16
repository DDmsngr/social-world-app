import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/core/links/deep_links.dart';
import 'package:social_world/core/share/share_service.dart';
import 'package:social_world/features/discover/domain/entities/city.dart';

void main() {
  test('город в сообщении — по точке, а не всегда Сочи', () {
    final spb = ShareService.message(
      target: LinkTarget.event,
      id: '1',
      title: 'Встреча друзей',
      city: Cities.nameNear(59.94, 30.31),
    );
    expect(spb, contains('📍 Санкт-Петербург'));
    expect(spb, isNot(contains('Сочи')));
  });

  test('без точки или далеко от городов строки с городом нет', () {
    expect(Cities.nameNear(null, null), isNull);
    expect(Cities.nameNear(64.5, 40.5), isNull); // Архангельск — не в списке
    final text = ShareService.message(target: LinkTarget.post, id: '1', title: 'Пост');
    expect(text, isNot(contains('📍')));
  });

  test('точка в черте пилотного города подписывается им', () {
    expect(Cities.nameNear(43.60, 39.73), 'Сочи');
  });
}
