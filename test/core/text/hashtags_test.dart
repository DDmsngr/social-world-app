import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/core/text/hashtags.dart';

void main() {
  test('теги на любом алфавите, без повторов, в нижнем регистре', () {
    expect(
      extractHashtags('Закат #СПб и #охтапарк, ещё раз #спб #2025 #a #kids_fashion'),
      ['спб', 'охтапарк', '2025', 'kids_fashion'],
    );
  });

  test('пустой текст и текст без тегов', () {
    expect(extractHashtags(null), isEmpty);
    expect(extractHashtags('просто # текст'), isEmpty);
  });

  test('тег из ссылки или ввода', () {
    expect(normalizeHashtag('  ##Закат '), 'закат');
  });
}
