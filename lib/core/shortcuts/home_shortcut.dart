import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../debug/app_log.dart';
import '../links/deep_links.dart';

/// Ярлык конкретного чата на рабочем столе телефона (Android 8+). Нажатие
/// открывает приложение сразу в этом чате — через обычную ссылку
/// `socialworld://chat/<id>`. Иконка — круглая аватарка собеседника, если
/// она есть, иначе значок приложения.
abstract final class HomeShortcut {
  static const _channel = MethodChannel('chawo/shortcuts');

  static bool get supported => !kIsWeb && Platform.isAndroid;

  /// true — система показала окно «Добавить на главный экран».
  static Future<bool> pinChat({
    required String conversationId,
    required String title,
    String? avatarUrl,
  }) async {
    if (!supported) return false;
    Uint8List? icon;
    if (avatarUrl != null && avatarUrl.startsWith('http')) {
      try {
        icon = await _roundIcon(avatarUrl);
      } catch (error) {
        AppLog.add('Иконка ярлыка не собралась: $error');
      }
    }
    try {
      final ok = await _channel.invokeMethod<bool>('pin', {
        'id': 'chat_$conversationId',
        'label': title.length > 24 ? '${title.substring(0, 23)}…' : title,
        'uri': DeepLinks.appUri(LinkTarget.chat, conversationId).toString(),
        'icon': icon,
      });
      return ok ?? false;
    } catch (error) {
      AppLog.add('Ярлык не создался: $error');
      return false;
    }
  }

  /// Аватарка, обрезанная в круг, 192×192 PNG.
  static Future<Uint8List> _roundIcon(String url) async {
    final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) throw StateError('HTTP ${response.statusCode}');
    final codec = await ui.instantiateImageCodec(
      response.bodyBytes,
      targetWidth: 192,
      targetHeight: 192,
    );
    final image = (await codec.getNextFrame()).image;
    const size = 192.0;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.clipPath(ui.Path()..addOval(const ui.Rect.fromLTWH(0, 0, size, size)));
    canvas.drawImage(image, ui.Offset.zero, ui.Paint()..filterQuality = ui.FilterQuality.high);
    final picture = recorder.endRecording();
    final rendered = await picture.toImage(size.toInt(), size.toInt());
    final bytes = await rendered.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    rendered.dispose();
    return bytes!.buffer.asUint8List();
  }
}
