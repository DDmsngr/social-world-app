import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:get_thumbnail_video/index.dart';
import 'package:get_thumbnail_video/video_thumbnail.dart';

import '../../../core/debug/app_log.dart';
import '../../../core/widgets/video_poster.dart';
import '../domain/entities/chat_message.dart';
import 'chat_media_cache.dart';

/// Крошечное превью фото или видео для цитаты ответа. Лежит в самой цитате
/// (base64), поэтому собеседник видит его без скачивания оригинала.
abstract final class ReplyPreview {
  static const _width = 72;
  static const _maxBytes = 24 * 1024;

  /// Превью сообщения из файла в кэше устройства; null, если файла нет или
  /// это не фото и не видео.
  static Future<String?> forMessage(ChatMessage message) async {
    final kind = message.kind;
    if (kind != MessageKind.image && kind != MessageKind.video && kind != MessageKind.videoNote) {
      return null;
    }
    try {
      final file = await ChatMediaCache.fileFor(message);
      if (!await file.exists()) return null;
      return kind == MessageKind.image ? await _image(file) : await _video(file.path);
    } catch (error) {
      AppLog.add('Превью для ответа: $error');
      return null;
    }
  }

  /// Кадр видео по ссылке (история с видео).
  static Future<String?> forVideoUrl(String url) async {
    final bytes = await VideoPoster.frame(url, _width);
    return _encode(bytes);
  }

  static Future<String?> _video(String path) async {
    final bytes = await VideoThumbnail.thumbnailData(
      video: path,
      imageFormat: ImageFormat.JPEG,
      maxWidth: _width,
      quality: 50,
      timeMs: 400,
    );
    return _encode(bytes);
  }

  static Future<String?> _image(File file) async {
    final codec = await ui.instantiateImageCodec(await file.readAsBytes(), targetWidth: _width);
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    return _encode(data?.buffer.asUint8List());
  }

  static String? _encode(Uint8List? bytes) {
    if (bytes == null || bytes.isEmpty || bytes.length > _maxBytes) return null;
    return base64Encode(bytes);
  }
}
