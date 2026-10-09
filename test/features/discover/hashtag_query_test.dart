import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/features/discover/presentation/widgets/map_controls.dart';

void main() {
  group('hashtagQuery', () {
    test('«#тег» превращается в тег без решётки и в нижнем регистре', () {
      expect(hashtagQuery('#закат'), 'закат');
      expect(hashtagQuery('  #Закат  '), 'закат');
      expect(hashtagQuery('#sochi2026'), 'sochi2026');
    });

    test('пробелы внутри схлопываются, пустой тег и обычный текст — не хэштег', () {
      expect(hashtagQuery('#мор ской'), 'морской');
      expect(hashtagQuery('#'), isNull);
      expect(hashtagQuery('# '), isNull);
      expect(hashtagQuery('закат'), isNull);
      expect(hashtagQuery(''), isNull);
    });
  });
}
