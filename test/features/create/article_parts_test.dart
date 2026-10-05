import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/features/create/domain/article_parts.dart';
import 'package:social_world/features/create/presentation/widgets/article_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const a = 'https://x/a.jpg';
  const b = 'https://x/b.jpg';

  group('parseArticle / serializeArticle', () {
    test('текст, фото, текст разбираются и собираются обратно', () {
      const md = 'Вот текст\n\n![фото]($a)\n\nПродолжение';
      final parts = parseArticle(md);
      expect(parts, hasLength(3));
      expect(parts[1], isA<MediaPart>());
      expect(serializeArticle(parts), md);
    });

    test('два фото подряд получают пустой текст между собой и по краям', () {
      final parts = parseArticle('![фото]($a)\n\n![фото]($b)');
      expect(parts.map((p) => p.runtimeType), [
        TextPart,
        MediaPart,
        TextPart,
        MediaPart,
        TextPart,
      ]);
      expect(serializeArticle(parts), '![фото]($a)\n\n![фото]($b)');
    });

    test('фото посреди абзаца выносится отдельным блоком', () {
      final parts = parseArticle('до ![фото]($a) после');
      expect(serializeArticle(parts), 'до \n\n![фото]($a)\n\n после');
    });

    test('пустая статья — один пустой текстовый блок', () {
      expect(parseArticle(''), hasLength(1));
      expect(serializeArticle(parseArticle('')), '');
    });
  });

  group('ArticleController', () {
    test('вставка делит текст по курсору', () {
      final c = ArticleController('Начало конец');
      final field = c.blocks.first.controller!;
      field.selection = const TextSelection.collapsed(offset: 6);
      c.insertMedia(a, 'фото');
      expect(c.mediaCount, 1);
      expect(c.markdown, 'Начало\n\n![фото]($a)\n\nконец');
      c.dispose();
    });

    test('несколько фото подряд встают по порядку выбора', () {
      final c = ArticleController('Текст');
      c.insertMedia(a, 'фото');
      c.insertMedia(b, 'фото');
      expect(c.markdown, 'Текст\n\n![фото]($a)\n\n![фото]($b)');
      c.dispose();
    });

    test('сдвиг меняет фото местами и пропускает пустое поле', () {
      final c = ArticleController('![фото]($a)\n\n![фото]($b)');
      final first = c.blocks.indexWhere((x) => x.isMedia);
      expect(c.canMove(first, -1), isFalse);
      c.move(first, 1);
      expect(c.markdown, '![фото]($b)\n\n![фото]($a)');
      c.dispose();
    });

    test('сдвиг фото выше текста', () {
      final c = ArticleController('Раз\n\n![фото]($a)\n\nДва');
      c.move(1, -1);
      expect(c.markdown, '![фото]($a)\n\nРаз\n\nДва');
      c.dispose();
    });

    test('удаление склеивает соседние тексты', () {
      final c = ArticleController('Раз\n\n![фото]($a)\n\nДва');
      c.remove(1);
      expect(c.mediaCount, 0);
      expect(c.markdown, 'Раз\n\nДва');
      c.dispose();
    });
  });
}
