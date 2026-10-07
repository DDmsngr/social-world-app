import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';

import 'instagram_archive.dart';

class _Part {
  _Part(this.input, this.archive);

  final InputFileStream input;
  final Archive archive;
}

/// Открытая выгрузка — один zip или несколько частей. Прежняя сеть режет
/// большую выгрузку на куски по 1–3 ГБ: публикации (JSON) лежат в одной части,
/// а фото и видео разбросаны по всем. Поэтому части читаются вместе, а файл
/// ищется в той, где он есть.
///
/// Каждый zip читается потоком с диска: целиком в память он не помещается.
class DataArchive {
  DataArchive._(this._parts, this.parsed);

  final List<_Part> _parts;
  final ParsedExport parsed;

  int get partCount => _parts.length;

  static Future<DataArchive> open(List<String> zipPaths) async {
    final parts = <_Part>[];
    try {
      for (final path in zipPaths) {
        final input = InputFileStream(path);
        try {
          parts.add(_Part(input, ZipDecoder().decodeStream(input)));
        } catch (_) {
          await input.close();
          rethrow;
        }
      }

      Object? read(ArchiveFile file) {
        final bytes = file.readBytes();
        if (bytes == null) return null;
        try {
          return jsonDecode(utf8.decode(bytes));
        } on FormatException {
          return null;
        }
      }

      final posts = <ImportedPost>[];
      final followers = <String>[];
      final following = <String>[];
      String? photo;

      for (final part in parts) {
        for (final file in part.archive) {
          if (!file.isFile) continue;
          final name = file.name;
          if (isPostsFile(name)) {
            posts.addAll(parsePosts(read(file)));
          } else if (isFollowersFile(name)) {
            followers.addAll(parseFollowers(read(file)));
          } else if (isFollowingFile(name)) {
            following.addAll(parseFollowing(read(file)));
          } else if (isProfilePhotosFile(name)) {
            photo ??= parseProfilePhoto(read(file));
          }
        }
      }

      return DataArchive._(
        parts,
        ParsedExport(
          // Одна и та же часть, выбранная дважды, или JSON, лежащий в двух
          // частях, не должны дать двойные публикации.
          posts: uniquePosts(posts),
          contacts: mergeContacts(followers: followers, following: following),
          profilePhotoEntry: photo,
          handle: zipPaths.map(handleFromArchiveName).nonNulls.firstOrNull,
        ),
      );
    } catch (_) {
      for (final part in parts) {
        await part.input.close();
      }
      rethrow;
    }
  }

  ArchiveFile? _find(String entry) {
    for (final part in _parts) {
      final file = part.archive.find(entry);
      if (file != null && file.isFile) return file;
    }
    return null;
  }

  /// Есть ли файл хоть в одной из выбранных частей.
  bool has(String entry) => _find(entry) != null;

  /// Распаковывает один файл архива в [dir] и возвращает путь к нему.
  Future<String?> extract(String entry, Directory dir, String name) async {
    final file = _find(entry);
    if (file == null) return null;
    final dot = entry.lastIndexOf('.');
    final ext = dot == -1 ? '' : entry.substring(dot);
    final path = '${dir.path}${Platform.pathSeparator}$name$ext';
    final output = OutputFileStream(path);
    file.writeContent(output, freeMemory: true);
    await output.close();
    return path;
  }

  Future<void> close() async {
    for (final part in _parts) {
      await part.input.close();
    }
  }
}
