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

  test('пак «Жиза»: 24 стикера парня, у каждого есть файл', () {
    final zhiza = packs.firstWhere((p) => p['id'] == 'zhiza');
    expect(zhiza['title'], 'Жиза');
    expect(zhiza['category'], 'мемы');
    final stickers = (zhiza['stickers'] as List).cast<Map<String, dynamic>>();
    expect(stickers, hasLength(24));
    for (final s in stickers) {
      expect(File('${root.path}/zhiza/${s['key']}.webp').existsSync(), isTrue, reason: s['key']);
    }
  });

  test('пак «Палыч»: 24 стикера, помечен 18+, у каждого есть файл', () {
    final palych = packs.firstWhere((p) => p['id'] == 'palych');
    expect(palych['title'], 'Палыч');
    expect(palych['description'], contains('18+'));
    final stickers = (palych['stickers'] as List).cast<Map<String, dynamic>>();
    expect(stickers, hasLength(24));
    for (final s in stickers) {
      expect(File('${root.path}/palych/${s['key']}.webp').existsSync(), isTrue, reason: s['key']);
    }
  });

  test('пак «Викинг»: три листа (8 + 8 + 12), помечен 18+, у каждого есть файл', () {
    final viking = packs.firstWhere((p) => p['id'] == 'viking');
    expect(viking['title'], 'Викинг');
    expect(viking['description'], contains('18+'));
    final stickers = (viking['stickers'] as List).cast<Map<String, dynamic>>();
    expect(stickers, hasLength(28));
    expect(stickers.first['key'], 'vse_pod_kontrolem');
    expect(stickers.last['key'], 'bodrogo_dnya');
    for (final s in stickers) {
      expect(File('${root.path}/viking/${s['key']}.webp').existsSync(), isTrue, reason: s['key']);
    }
  });

  test('пак «Алекса»: три листа (23 + 24 + 24), без «победы», у каждого есть файл', () {
    final alexa = packs.firstWhere((p) => p['id'] == 'alexa');
    expect(alexa['title'], 'Алекса');
    final stickers = (alexa['stickers'] as List).cast<Map<String, dynamic>>();
    expect(stickers, hasLength(71));
    // Первый лист — без подписей, второй дописан в конец.
    expect(stickers.first['key'], 'wave');
    expect(stickers.last['key'], 'o_kak');
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
