import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../config/env.dart';
import 'exif_strip.dart';

/// Загрузка фотографий и видео в Supabase Storage.
///
/// Путь всегда начинается с id пользователя: политика бакета разрешает запись
/// только в свою папку, так что чужое имя в пути просто не пройдёт.
class MediaUploader {
  MediaUploader(this._client, {required this.bucket});

  final SupabaseClient _client;
  final String bucket;

  static const _uuid = Uuid();

  static const _mime = {
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.png': 'image/png',
    '.webp': 'image/webp',
    '.heic': 'image/heic',
    '.gif': 'image/gif',
    '.mp4': 'video/mp4',
    '.m4v': 'video/x-m4v',
    '.mov': 'video/quicktime',
    '.webm': 'video/webm',
  };

  /// [onProgress] — доля отправленного от 0 до 1. Если он задан, файл уходит
  /// потоком с диска (видео не читается в память целиком) и прогресс честный.
  Future<String> upload(String localPath, {void Function(double)? onProgress}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw const AuthException('Нет активной сессии');

    final dot = localPath.lastIndexOf('.');
    final extension = dot == -1 ? '.jpg' : localPath.substring(dot).toLowerCase();
    final objectPath = '$userId/${_uuid.v4()}$extension';

    if (onProgress == null) {
      // Бакеты публичные: геометки и модель телефона из снимка уходить не должны.
      final bytes = stripJpegMetadata(await File(localPath).readAsBytes());
      await _client.storage
          .from(bucket)
          .uploadBinary(
            objectPath,
            bytes,
            fileOptions: const FileOptions(cacheControl: '31536000'),
          );
    } else {
      await _uploadStreamed(localPath, extension, objectPath, onProgress);
    }

    return _client.storage.from(bucket).getPublicUrl(objectPath);
  }

  Future<void> _uploadStreamed(
    String localPath,
    String extension,
    String objectPath,
    void Function(double) onProgress,
  ) async {
    final session = _client.auth.currentSession;
    if (session == null) throw const AuthException('Нет активной сессии');

    final Stream<List<int>> body;
    final int length;
    if (extension == '.jpg' || extension == '.jpeg') {
      final Uint8List bytes = stripJpegMetadata(await File(localPath).readAsBytes());
      length = bytes.length;
      body = Stream<List<int>>.value(bytes);
    } else {
      length = await File(localPath).length();
      body = File(localPath).openRead();
    }

    final request = http.StreamedRequest(
      'POST',
      Uri.parse('${Env.supabaseUrl}/storage/v1/object/$bucket/$objectPath'),
    )
      ..contentLength = length
      ..headers.addAll({
        'apikey': Env.supabaseAnonKey,
        'Authorization': 'Bearer ${session.accessToken}',
        'Content-Type': _mime[extension] ?? 'application/octet-stream',
        'cache-control': 'max-age=31536000',
      });

    final client = http.Client();
    try {
      final response = client.send(request);
      var sent = 0;
      onProgress(0);
      // addStream слушает источник с учётом заполнения сокета, поэтому доля
      // растёт по мере реальной отправки, а не мгновенно.
      await request.sink.addStream(
        body.map((chunk) {
          sent += chunk.length;
          onProgress(length == 0 ? 1 : sent / length);
          return chunk;
        }),
      );
      await request.sink.close();

      final result = await response;
      if (result.statusCode < 200 || result.statusCode >= 300) {
        final text = await result.stream.bytesToString();
        throw StorageException(
          text.isEmpty ? 'Загрузка не удалась' : text,
          statusCode: '${result.statusCode}',
        );
      }
      onProgress(1);
    } finally {
      client.close();
    }
  }
}
