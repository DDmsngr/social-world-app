import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/features/chat/domain/stickers.dart';

void main() {
  final manifest = jsonDecode(File('assets/stickers/manifest.json').readAsStringSync())
      as Map<String, dynamic>;
  final packs = (manifest['packs'] as List).cast<Map<String, dynamic>>();
  final families = (manifest['families'] as Map<String, dynamic>).keys.toSet();

  test('пак «Алекса»: 23 стикера (без «победы»), у каждого есть файл', () {
    final alexa = packs.firstWhere((p) => p['id'] == 'alexa');
    expect(alexa['title'], 'Алекса');
    final stickers = (alexa['stickers'] as List).cast<Map<String, dynamic>>();
    expect(stickers, hasLength(23));
    expect(stickers.map((s) => s['id']), isNot(contains('alexa.victory')));
    expect(File('assets/stickers/alexa/victory.webp').existsSync(), isFalse);
    for (final s in stickers) {
      final id = s['id'] as String;
      expect(id, startsWith('alexa.'));
      expect(File(stickerAsset(id)!).existsSync(), isTrue, reason: id);
    }
  });

  test('все стикеры манифеста: id не повторяются, семейства эмоций известны', () {
    final ids = <String>{};
    for (final p in packs) {
      for (final s in (p['stickers'] as List).cast<Map<String, dynamic>>()) {
        expect(ids.add(s['id'] as String), isTrue, reason: 'повтор ${s['id']}');
        for (final f in (s['emotions'] as List)) {
          expect(families, contains(f), reason: '${s['id']}: $f');
        }
      }
    }
  });
}
