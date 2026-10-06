import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../config/env.dart';
import 'exif_strip.dart';
import 'file_too_large.dart';
import 'video_compressor.dart';

/// Загрузка фотографий и видео в Supabase Storage.
///
/// Путь всегда начинается с id пользователя: политика бакета разрешает запись
/// только в свою папку, так что чужое имя в пути просто не пройдёт.
///
/// Крупные файлы (больше [_chunk]) идут по частям через протокол докачки
/// (TUS): API ходит через прокси в РФ, а канал до облака рвёт длинные
/// соединения — 29-мегабайтное видео одним запросом обрывалось на середине.
/// Каждая часть — отдельный запрос; оборвалась — сервер говорит, сколько
/// дошло, и отправка продолжается с этого места.
class MediaUploader {
  MediaUploader(this._client, {required this.bucket});

  final SupabaseClient _client;
  final String bucket;

  static const _uuid = Uuid();

  /// Размер части. Хранилище Supabase принимает при докачке ровно 6 МБ
  /// (последняя часть — сколько осталось).
  static const _chunk = 6 * 1024 * 1024;
  static const _attempts = 5;

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

  /// [onProgress] — доля готового от 0 до 1. Тяжёлое видео сначала сжимается
  /// на телефоне (первые 40% полосы), потом уходит; [onStage] сообщает, что
  /// происходит сейчас.
  Future<String> upload(
    String localPath, {
    void Function(double)? onProgress,
    void Function(String stage)? onStage,
  }) async {
    final size = await File(localPath).length();
    if (!VideoCompressor.shouldCompress(localPath, size)) {
      return _send(localPath, onProgress: onProgress);
    }

    onStage?.call('Сжимаем видео');
    onProgress?.call(0);
    try {
      final compressed = await VideoCompressor.compress(
        localPath,
        onProgress: (p) => onProgress?.call(p * 0.4),
      );
      onStage?.call('Загружаем видео');
      return await _send(
        compressed.path,
        onProgress: (p) => onProgress?.call(0.4 + p * 0.6),
      );
    } finally {
      await VideoCompressor.cleanup();
    }
  }

  Future<String> _send(String localPath, {void Function(double)? onProgress}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw const AuthException('Нет активной сессии');

    final dot = localPath.lastIndexOf('.');
    final extension = dot == -1 ? '.jpg' : localPath.substring(dot).toLowerCase();
    final objectPath = '$userId/${_uuid.v4()}$extension';
    final mime = _mime[extension] ?? 'application/octet-stream';

    // Бакеты публичные: геометки и модель телефона из снимка уходить не должны.
    final isJpeg = extension == '.jpg' || extension == '.jpeg';
    final Uint8List? jpeg = isJpeg ? stripJpegMetadata(await File(localPath).readAsBytes()) : null;
    final length = jpeg?.length ?? await File(localPath).length();
    if (length > maxUploadBytes) throw FileTooLargeException(length);

    if (length > _chunk) {
      await _uploadResumable(
        objectPath: objectPath,
        mime: mime,
        length: length,
        read: jpeg != null
            ? (offset, size) async => Uint8List.sublistView(jpeg, offset, offset + size)
            : _fileReader(localPath),
        onProgress: onProgress,
      );
    } else {
      onProgress?.call(0);
      await _client.storage
          .from(bucket)
          .uploadBinary(
            objectPath,
            jpeg ?? await File(localPath).readAsBytes(),
            fileOptions: FileOptions(cacheControl: '31536000', contentType: mime),
          );
      onProgress?.call(1);
    }

    return _client.storage.from(bucket).getPublicUrl(objectPath);
  }

  Future<Uint8List> Function(int offset, int size) _fileReader(String path) {
    return (offset, size) async {
      final file = await File(path).open();
      try {
        await file.setPosition(offset);
        return await file.read(size);
      } finally {
        await file.close();
      }
    };
  }

  Map<String, String> _headers() {
    final session = _client.auth.currentSession;
    if (session == null) throw const AuthException('Нет активной сессии');
    return {
      'apikey': Env.supabaseAnonKey,
      'Authorization': 'Bearer ${session.accessToken}',
      'Tus-Resumable': '1.0.0',
    };
  }

  Future<void> _uploadResumable({
    required String objectPath,
    required String mime,
    required int length,
    required Future<Uint8List> Function(int offset, int size) read,
    void Function(double)? onProgress,
  }) async {
    String b64(String value) => base64.encode(utf8.encode(value));
    final base = Uri.parse(Env.supabaseUrl);
    final client = http.Client();
    try {
      final create = await client
          .post(
            base.replace(path: '/storage/v1/upload/resumable'),
            headers: {
              ..._headers(),
              'Upload-Length': '$length',
              'Upload-Metadata': [
                'bucketName ${b64(bucket)}',
                'objectName ${b64(objectPath)}',
                'contentType ${b64(mime)}',
                'cacheControl ${b64('31536000')}',
              ].join(','),
              'x-upsert': 'false',
            },
          )
          .timeout(const Duration(seconds: 30));
      final location = create.headers['location'];
      if (create.statusCode != 201 || location == null) {
        throw StorageException(
          create.body.isEmpty ? 'Загрузка не началась' : create.body,
          statusCode: '${create.statusCode}',
        );
      }
      // Сервер отвечает адресом облака, а ходить надо через свой прокси —
      // берём из ответа только путь.
      final target = base.replace(path: Uri.parse(location).path);

      var offset = 0;
      var failures = 0;
      onProgress?.call(0);
      while (offset < length) {
        final size = min(_chunk, length - offset);
        try {
          final bytes = await read(offset, size);
          final start = offset;
          offset = await _patch(client, target, start, bytes, (sent) {
            onProgress?.call((start + sent) / length);
          });
          failures = 0;
        } catch (error) {
          if (error is StorageException && error.statusCode != null &&
              !(error.statusCode!.startsWith('5') || error.statusCode == '409')) {
            rethrow;
          }
          failures++;
          if (failures >= _attempts) rethrow;
          await Future<void>.delayed(Duration(seconds: 2 * failures));
          // Где остановились — знает только сервер: часть могла дойти целиком,
          // даже если ответ потерялся по дороге.
          try {
            final head = await client
                .head(target, headers: _headers())
                .timeout(const Duration(seconds: 20));
            final known = int.tryParse(head.headers['upload-offset'] ?? '');
            if (known != null) offset = known;
          } catch (_) {}
        }
      }
      onProgress?.call(1);
    } finally {
      client.close();
    }
  }

  /// Отправляет одну часть, возвращает новое смещение от сервера.
  Future<int> _patch(
    http.Client client,
    Uri target,
    int offset,
    Uint8List bytes,
    void Function(int sent) onSent,
  ) async {
    final request = http.StreamedRequest('PATCH', target)
      ..contentLength = bytes.length
      ..headers.addAll({
        ..._headers(),
        'Upload-Offset': '$offset',
        'Content-Type': 'application/offset+octet-stream',
      });
    final response = client.send(request).timeout(const Duration(minutes: 3));

    // Кусками по 64 КБ: полоса загрузки движется по мере отправки.
    const slice = 64 * 1024;
    var sent = 0;
    await request.sink.addStream(
      Stream.fromIterable([
        for (var i = 0; i < bytes.length; i += slice)
          Uint8List.sublistView(bytes, i, min(i + slice, bytes.length)),
      ]).map((part) {
        sent += part.length;
        onSent(sent);
        return part;
      }),
    );
    await request.sink.close();

    final result = await response;
    final body = await result.stream.bytesToString();
    if (result.statusCode != 204) {
      throw StorageException(
        body.isEmpty ? 'Часть не загрузилась' : body,
        statusCode: '${result.statusCode}',
      );
    }
    return int.tryParse(result.headers['upload-offset'] ?? '') ?? offset + bytes.length;
  }
}
