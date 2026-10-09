import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/features/chat/data/link_preview_fetcher.dart';
import 'package:social_world/features/chat/domain/entities/chat_meta.dart';

void main() {
  test('первая ссылка берётся без хвостовой пунктуации', () {
    expect(LinkPreviewFetcher.firstUrl('смотри https://ozon.ru/t/LCSTHXa.'), 'https://ozon.ru/t/LCSTHXa');
    expect(LinkPreviewFetcher.firstUrl('(http://a.ru/x?y=1) и https://b.ru'), 'http://a.ru/x?y=1');
    expect(LinkPreviewFetcher.firstUrl('без ссылок'), isNull);
  });

  test('превью едет в meta и читается обратно', () {
    const meta = ChatMeta(
      linkPreview: LinkPreview(url: 'https://a.ru/x', title: 'Заголовок', description: 'Описание'),
    );
    expect(meta.isEmpty, isFalse);
    final back = ChatMeta.fromJson(meta.toJson());
    expect(back.linkPreview!.url, 'https://a.ru/x');
    expect(back.linkPreview!.title, 'Заголовок');
    expect(back.linkPreview!.imageB64, isNull);
  });

  test('чужая meta без http-ссылки превью не создаёт', () {
    expect(ChatMeta.fromJson({'l': {'u': 'javascript:alert(1)'}}).linkPreview, isNull);
  });
}
