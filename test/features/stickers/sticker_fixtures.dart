import 'dart:convert';
import 'dart:io';

import 'package:social_world/features/chat/domain/stickers.dart';
import 'package:social_world/features/chat/presentation/widgets/sticker_views.dart';
import 'package:social_world/features/stickers/data/sticker_repository.dart';

/// Каталог в том виде, в каком его отдаёт sticker_catalog() (0078), собранный
/// из настоящих исходников паков tools/stickers/packs — тех же, что
/// публикует publish_packs.py.
Map<String, dynamic> catalogJsonFromSources() {
  final root = Directory('tools/stickers/packs');
  final families = jsonDecode(File('${root.path}/families.json').readAsStringSync());
  final packs = <Map<String, dynamic>>[];
  final dirs = root.listSync().whereType<Directory>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final dir in dirs) {
    final meta = jsonDecode(File('${dir.path}/pack.json').readAsStringSync()) as Map<String, dynamic>;
    final id = meta['id'] as String;
    packs.add({
      'id': id,
      'title': meta['title'],
      'description': meta['description'],
      'publisher': meta['publisher'],
      'category': meta['category'],
      'cover': '$id/thumb/${(meta['stickers'] as List).first['key']}.webp',
      'version': meta['version'],
      'status': meta['status'],
      'sort_order': meta['sort_order'],
      'stickers': [
        for (final s in meta['stickers'] as List)
          {
            'id': '$id.${s['key']}',
            'emoji': s['emoji'],
            'title': s['title'],
            'synonyms': s['synonyms'],
            'emotions': s['emotions'],
            'image': '$id/${s['key']}.webp',
            'thumb': '$id/thumb/${s['key']}.webp',
          },
      ],
    });
  }
  packs.sort((a, b) => (a['sort_order'] as int).compareTo(b['sort_order'] as int));
  return {'families': families, 'packs': packs};
}

StickerCatalog catalogFromSources() => StickerCatalog.fromJson(catalogJsonFromSources());

/// Тестам — свой адрес бакета и картинки без сети.
void useTestStickerImages() {
  StickerUrls.baseForTest = 'https://test/stickers';
  StickerImage.offlineForTests = true;
}

/// Сервер магазина в памяти: ведёт себя как база с RLS для одного
/// пользователя (повторная установка — без дубля, снятый с публикации пак не
/// ставится), умеет падать по команде.
class FakeStickerBackend implements StickerBackend {
  FakeStickerBackend({Map<String, dynamic>? catalog, List<String>? installed})
    : _catalog = catalog ?? catalogJsonFromSources(),
      installedIds = [...?installed];

  final Map<String, dynamic> _catalog;
  final List<String> installedIds;

  bool failCatalog = false;
  bool failWrites = false;
  int catalogCalls = 0;

  @override
  Future<Map<String, dynamic>> catalog() async {
    catalogCalls++;
    if (failCatalog) throw const SocketException('нет сети');
    return _catalog;
  }

  @override
  Future<List<String>> installed() async {
    if (failCatalog) throw const SocketException('нет сети');
    return [...installedIds];
  }

  @override
  Future<void> install(String packId) async {
    if (failWrites) throw const SocketException('нет сети');
    final pack = (_catalog['packs'] as List).where((p) => p['id'] == packId).firstOrNull;
    if (pack == null || pack['status'] != 'published') {
      throw StateError('new row violates row-level security policy');
    }
    if (!installedIds.contains(packId)) installedIds.add(packId);
  }

  @override
  Future<void> uninstall(String packId) async {
    if (failWrites) throw const SocketException('нет сети');
    installedIds.remove(packId);
  }
}
