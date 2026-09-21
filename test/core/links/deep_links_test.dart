import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/core/links/deep_links.dart';
import 'package:social_world/core/permissions/content_permissions.dart';
import 'package:social_world/core/text/markdown_preview.dart';
import 'package:social_world/core/widgets/markdown_view.dart';

void main() {
  group('DeepLinks', () {
    test('своя схема и веб-ссылка разбираются в один объект', () {
      final app = DeepLinks.parse(Uri.parse('socialworld://event/abc-123'));
      final web = DeepLinks.parse(DeepLinks.shareUri(LinkTarget.event, 'abc-123'));
      expect(app, DeepLink(LinkTarget.event, 'abc-123'));
      expect(web, app);
      expect(app!.location, '/event/abc-123');
    });

    test('вход через VK/Яндекс и чужие адреса — не ссылки на объекты', () {
      expect(DeepLinks.parse(Uri.parse('socialworld://auth-callback#a=b')), isNull);
      expect(DeepLinks.parse(Uri.parse('https://evil.example/o/post/abcd')), isNull);
      expect(DeepLinks.parse(Uri.parse('socialworld://post/..%2Fx')), isNull);
    });
  });

  group('ContentPermissions', () {
    test('чужое: жалоба можно, править нельзя', () {
      const p = ContentPermissions(viewerId: 'me', ownerId: 'other');
      expect(p.canReport, isTrue);
      expect(p.canEdit, isFalse);
      expect(p.requireOwner, throwsA(isA<PermissionDeniedException>()));
    });

    test('своё: править можно, жаловаться нельзя', () {
      const p = ContentPermissions(viewerId: 'me', ownerId: 'me');
      expect(p.canEdit, isTrue);
      expect(p.canReport, isFalse);
      expect(p.requireForeign, throwsA(isA<PermissionDeniedException>()));
    });
  });

  group('Markdown', () {
    test('опасные схемы ссылок отбрасываются', () {
      expect(isSafeLink('https://a.ru'), isTrue);
      expect(isSafeLink('javascript:alert(1)'), isFalse);
      expect(isSafeLink('intent://x'), isFalse);
      expect(isSafeLink(null), isFalse);
    });

    test('превью статьи без разметки', () {
      final text = markdownPreview('## Заголовок\n\n**Жирный** [ссылка](http://x.ru) ![i](http://y)');
      expect(text, 'Заголовок Жирный ссылка');
    });
  });
}