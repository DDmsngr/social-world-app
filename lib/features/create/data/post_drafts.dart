import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../../core/debug/app_log.dart';

/// Черновик момента или статьи. Лежит на самом телефоне; фото момента
/// хранятся путями к файлам и пропадают из черновика, если файл удалили.
class PostDraft {
  const PostDraft({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.attachmentPaths,
    required this.updatedAt,
    this.tags = const [],
  });

  final String id;
  final List<String> tags;

  /// `moment` или `article` (как сегмент маршрута создания).
  final String kind;
  final String title;
  final String body;
  final List<String> attachmentPaths;
  final DateTime updatedAt;

  bool get isArticle => kind == 'article';

  /// Короткая подпись в списке: заголовок статьи или начало текста.
  String get label {
    final head = title.trim();
    if (head.isNotEmpty) return head;
    final text = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isNotEmpty) return text.length > 80 ? '${text.substring(0, 80)}…' : text;
    return attachmentPaths.isNotEmpty ? 'Только фото' : 'Пустой черновик';
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind,
    'title': title,
    'body': body,
    'files': attachmentPaths,
    'tags': tags,
    'at': updatedAt.toIso8601String(),
  };

  static PostDraft? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final kind = raw['kind'];
    if (id is! String || kind is! String) return null;
    return PostDraft(
      id: id,
      kind: kind,
      title: raw['title'] as String? ?? '',
      body: raw['body'] as String? ?? '',
      attachmentPaths: [
        for (final p in (raw['files'] as List? ?? const []))
          if (p is String && File(p).existsSync()) p,
      ],
      updatedAt: DateTime.tryParse('${raw['at']}') ?? DateTime.now(),
      tags: [
        for (final t in (raw['tags'] as List? ?? const []))
          if (t is String) t,
      ],
    );
  }
}

/// Хранилище черновиков (на устройстве). Новые сверху.
abstract final class PostDrafts {
  static const _key = 'post_drafts';
  static const _uuid = Uuid();

  static Future<List<PostDraft>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return const [];
      final list = [
        for (final item in jsonDecode(raw) as List) ?PostDraft.fromJson(item),
      ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return list;
    } catch (error) {
      AppLog.add('Черновики не прочитались: $error');
      return const [];
    }
  }

  /// Сохраняет черновик; без [id] создаётся новый. Возвращает id.
  static Future<String> save({
    String? id,
    required String kind,
    required String title,
    required String body,
    required List<String> attachmentPaths,
    List<String> tags = const [],
  }) async {
    final draft = PostDraft(
      id: id ?? _uuid.v4(),
      kind: kind,
      title: title,
      body: body,
      attachmentPaths: attachmentPaths,
      tags: tags,
      updatedAt: DateTime.now(),
    );
    final all = [for (final d in await load()) if (d.id != draft.id) d, draft];
    await _write(all);
    return draft.id;
  }

  static Future<void> delete(String id) async {
    await _write([for (final d in await load()) if (d.id != id) d]);
  }

  static Future<void> _write(List<PostDraft> all) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode([for (final d in all) d.toJson()]));
  }
}

final postDraftsProvider = FutureProvider.autoDispose<List<PostDraft>>(
  (ref) => PostDrafts.load(),
);
