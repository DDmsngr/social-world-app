import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../debug/app_log.dart';
import '../theme/app_colors.dart';

/// Кадр-превью видео по ссылке. Достаётся один раз и держится в памяти
/// (последние 80), поэтому при прокрутке сетки или ленты не мигает и не
/// качается заново. Пока кадра нет (или не вышло достать) — тёмная плитка
/// со значком; [overlay] рисуется поверх в любом случае.
class VideoPoster extends StatelessWidget {
  const VideoPoster({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.maxWidth = 480,
    this.showPlay = true,
  });

  final String url;
  final BoxFit fit;
  final int maxWidth;

  /// Круглая кнопка «играть» посередине.
  final bool showPlay;

  // Литерал `{}` — LinkedHashMap: порядок вставки нужен для вытеснения старого.
  static final _cache = <String, Uint8List>{};
  static final _pending = <String, Future<Uint8List?>>{};

  static Future<Uint8List?> frame(String url, int maxWidth) {
    final cached = _cache.remove(url);
    if (cached != null) {
      _cache[url] = cached;
      return Future.value(cached);
    }
    return _pending[url] ??= () async {
      try {
        final bytes = await VideoThumbnail.thumbnailData(
          video: url,
          imageFormat: ImageFormat.JPEG,
          maxWidth: maxWidth,
          quality: 75,
          timeMs: 400,
        );
        if (bytes != null && bytes.isNotEmpty) {
          _cache[url] = bytes;
          if (_cache.length > 80) _cache.remove(_cache.keys.first);
        }
        return bytes;
      } catch (error) {
        AppLog.add('Превью видео не достали: $error');
        return null;
      } finally {
        _pending.remove(url);
      }
    }();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: frame(url, maxWidth),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        return Stack(
          fit: StackFit.expand,
          children: [
            if (bytes != null)
              Image.memory(bytes, fit: fit, gaplessPlayback: true)
            else
              const ColoredBox(color: Color(0xFF15151A)),
            if (showPlay)
              Center(
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.ink.withAlpha(0x99),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.play_arrow, color: Colors.white, size: 28),
                ),
              ),
          ],
        );
      },
    );
  }
}
