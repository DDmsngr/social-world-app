import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:video_compress/video_compress.dart';

import '../debug/app_log.dart';
import 'file_too_large.dart';

/// Ролики тяжелее этого сжимаются на телефоне перед отправкой: хранилище не
/// принимает файлы больше 50 МБ, а ролик с камеры за полминуты легко весит
/// сотню. Лёгкие ролики уходят как есть, без потери качества.
const compressVideoAboveBytes = 20 * 1024 * 1024;

/// Исходный ролик тяжелее этого не берём: сжимать его на телефоне слишком долго.
const maxVideoSourceBytes = 500 * 1024 * 1024;

String videoTooBigMessage(int bytes) =>
    'Ролик ${(bytes / (1024 * 1024)).round()} МБ слишком тяжёлый — '
    'выберите короче, до ${maxVideoSourceBytes ~/ (1024 * 1024)} МБ';

const _videoExtensions = {'.mp4', '.mov', '.m4v', '.3gp', '.mkv', '.webm'};

bool isVideoPath(String path) {
  final dot = path.lastIndexOf('.');
  return dot != -1 && _videoExtensions.contains(path.substring(dot).toLowerCase());
}

/// Сжатие видео средствами телефона (Android/iOS): 720p, звук сохраняется.
/// Если после первого прохода файл всё ещё не лезет в [maxUploadBytes],
/// делается второй — в 480p.
abstract final class VideoCompressor {
  static bool get supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static bool shouldCompress(String path, int bytes) =>
      supported && isVideoPath(path) && bytes > compressVideoAboveBytes;

  /// Возвращает сжатый файл. Исходный не трогает. [onProgress] — доля 0–1.
  static Future<File> compress(String path, {void Function(double)? onProgress}) async {
    var file = await _pass(path, VideoQuality.Res1280x720Quality, onProgress);
    var size = await file.length();
    if (size > maxUploadBytes) {
      AppLog.add('Сжатие 720p дало ${size ~/ (1024 * 1024)} МБ, пробуем 480p');
      file = await _pass(file.path, VideoQuality.Res640x480Quality, null);
      size = await file.length();
    }
    AppLog.add('Ролик сжат до ${size ~/ (1024 * 1024)} МБ');
    return file;
  }

  static Future<File> _pass(
    String path,
    VideoQuality quality,
    void Function(double)? onProgress,
  ) async {
    final subscription = VideoCompress.compressProgress$.subscribe(
      (percent) => onProgress?.call((percent / 100).clamp(0.0, 1.0)),
    );
    try {
      final info = await VideoCompress.compressVideo(
        path,
        quality: quality,
        deleteOrigin: false,
        includeAudio: true,
      );
      final file = info?.file;
      if (file == null) throw StateError('Не удалось сжать видео');
      return file;
    } finally {
      subscription.unsubscribe();
    }
  }

  /// Временные файлы библиотеки лежат в кэше; после отправки их стираем.
  static Future<void> cleanup() async {
    try {
      await VideoCompress.deleteAllCache();
    } catch (error) {
      AppLog.add('Кэш сжатия не очистился: $error');
    }
  }
}
