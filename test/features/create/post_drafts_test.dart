import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:social_world/features/create/data/post_drafts.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('черновик сохраняется, правится по id и удаляется', () async {
    final id = await PostDrafts.save(
      kind: 'article',
      title: 'Заголовок',
      body: 'Текст статьи',
      attachmentPaths: const [],
    );
    var all = await PostDrafts.load();
    expect(all.single.id, id);
    expect(all.single.isArticle, isTrue);
    expect(all.single.label, 'Заголовок');

    await PostDrafts.save(id: id, kind: 'article', title: 'Новый', body: 'Текст', attachmentPaths: const []);
    all = await PostDrafts.load();
    expect(all.length, 1, reason: 'тот же id — правка, не копия');
    expect(all.single.title, 'Новый');

    await PostDrafts.delete(id);
    expect(await PostDrafts.load(), isEmpty);
  });

  test('новый черновик встаёт выше старого; подпись из текста, если нет заголовка', () async {
    await PostDrafts.save(kind: 'moment', title: '', body: 'первый', attachmentPaths: const []);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await PostDrafts.save(kind: 'moment', title: '', body: 'второй\nс переносом', attachmentPaths: const []);
    final all = await PostDrafts.load();
    expect(all.map((d) => d.label), ['второй с переносом', 'первый']);
  });
}
