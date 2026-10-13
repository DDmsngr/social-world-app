import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Исходники паков для магазина (tools/stickers/packs): то, что публикует
// publish_packs.py. Битый pack.json сервер не примет, проверяем заранее.
void main() {
  final root = Directory('tools/stickers/packs');
  final families = (jsonDecode(File('${root.path}/families.json').readAsStringSync()) as Map).keys.toSet();
  final packs = [
    for (final dir in root.listSync().whereType<Directory>())
      jsonDecode(File('${dir.path}/pack.json').readAsStringSync()) as Map<String, dynamic>,
  ];

  test('пак «Алекса»: 23 стикера (без «победы»), у каждого есть файл', () {
    final alexa = packs.firstWhere((p) => p['id'] == 'alexa');
    expect(alexa['title'], 'Алекса');
    final stickers = (alexa['stickers'] as List).cast<Map<String, dynamic>>();
    expect(stickers, hasLength(23));
    expect(stickers.map((s) => s['key']), isNot(contains('victory')));
    expect(File('${root.path}/alexa/victory.webp').existsSync(), isFalse);
    for (final s in stickers) {
      expect(File('${root.path}/alexa/${s['key']}.webp').existsSync(), isTrue, reason: s['key']);
    }
  });

  test('все паки: ключи не повторяются, семейства известны, лишних картинок нет', () {
    for (final pack in packs) {
      final id = pack['id'] as String;
      expect(RegExp(r'^[a-z0-9_]{1,32}$').hasMatch(id), isTrue, reason: id);
      expect(['draft', 'review', 'published', 'archived'], contains(pack['status']), reason: id);
      final keys = <String>{};
      for (final s in (pack['stickers'] as List).cast<Map<String, dynamic>>()) {
        expect(keys.add(s['key'] as String), isTrue, reason: '$id: повтор ${s['key']}');
        expect(s['title'], isNotEmpty);
        expect(s['emoji'], isNotEmpty);
        for (final f in (s['emotions'] as List)) {
          expect(families, contains(f), reason: '$id.${s['key']}: $f');
        }
      }
      final files = Directory('${root.path}/$id')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.webp'))
          .map((f) => f.uri.pathSegments.last.replaceAll('.webp', ''))
          .toSet();
      expect(files, keys, reason: '$id: картинки и pack.json не сходятся');
    }
  });
}
