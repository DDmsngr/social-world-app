import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/features/channels/presentation/widgets/channel_post_card.dart';

void main() {
  test('превью статьи не режет разметку фото и берёт только первое фото', () {
    final long = 'а' * 900;
    final text = '# Заголовок\n\nНачало.\n\n![фото](https://x/1.jpg)\n\n$long\n\n![фото](https://x/2.jpg)\n\nКонец.';
    final preview = channelPostPreview(text);
    expect(preview, contains('![фото](https://x/1.jpg)'));
    expect(preview, isNot(contains('2.jpg')));
    expect(preview, isNot(contains('Конец.')));
    expect(preview.endsWith('…'), isTrue);
    expect(RegExp(r'!\[[^\]]*\]\([^)]*$').hasMatch(preview), isFalse);
  });
}
