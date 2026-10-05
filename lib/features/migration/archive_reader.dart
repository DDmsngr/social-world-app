import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';

import 'instagram_archive.dart';

/// Открытый zip с выгрузкой. Читается потоком с диска: архив с видео весит
/// гигабайты и целиком в память не помещается. Фото и видео достаются из него
/// по одному, когда дело доходит до публикации.
class DataArchive {
  DataArchive._(this._input, this._archive, this.parsed);

  final InputFileStream _input;
  final Archive _archive;
  final ParsedExport parsed;

  static Future<DataArchive> open(String zipPath) async {
    final input = InputFileStream(zipPath);
    try {
      final archive = ZipDecoder().decodeStream(input);

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

      for (final file in archive) {
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

      // Старые публикации первыми: в ленте они встанут в исходном порядке.
      posts.sort(
        (a, b) => (a.takenAt ?? DateTime(0)).compareTo(b.takenAt ?? DateTime(0)),
      );

      return DataArchive._(
        input,
        archive,
        ParsedExport(
          posts: posts,
          contacts: mergeContacts(followers: followers, following: following),
          profilePhotoEntry: photo,
          handle: handleFromArchiveName(zipPath),
        ),
      );
    } catch (_) {
      await input.close();
      rethrow;
    }
  }

  /// Распаковывает один файл архива в [dir] и возвращает путь к нему.
  Future<String?> extract(String entry, Directory dir, String name) async {
    final file = _archive.find(entry);
    if (file == null || !file.isFile) return null;
    final dot = entry.lastIndexOf('.');
    final ext = dot == -1 ? '' : entry.substring(dot);
    final path = '${dir.path}${Platform.pathSeparator}$name$ext';
    final output = OutputFileStream(path);
    file.writeContent(output, freeMemory: true);
    await output.close();
    return path;
  }

  Future<void> close() => _input.close();
}
