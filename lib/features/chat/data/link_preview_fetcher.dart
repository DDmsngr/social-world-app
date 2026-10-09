import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:http/http.dart' as http;

import '../../../core/debug/app_log.dart';
import '../domain/entities/chat_meta.dart';

/// Превью ссылки для сообщения. Страницу открывает телефон отправителя при
/// отправке, результат уезжает внутри сообщения: получатель к сайту не
/// обращается и свой адрес ему не показывает.
abstract final class LinkPreviewFetcher {
  static final _urlPattern = RegExp(r'https?://[^\s<>"]+', caseSensitive: false);
  static const _maxPage = 256 * 1024;
  static const _maxImage = 2 * 1024 * 1024;
  static const _imageWidth = 96;
  static const _maxImageB64 = 20 * 1024;

  /// Первая ссылка в тексте или null.
  static String? firstUrl(String text) {
    final match = _urlPattern.firstMatch(text);
    if (match == null) return null;
    // Хвостовая пунктуация («…ссылка.») к адресу не относится.
    return match.group(0)!.replaceFirst(RegExp(r'[).,;:!?»]+$'), '');
  }

  /// Превью или null: сайт не ответил, не страница, нечего показать.
  static Future<LinkPreview?> fetch(String text, {Duration timeout = const Duration(seconds: 4)}) async {
    final url = firstUrl(text);
    if (url == null) return null;
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasAuthority || _isLocal(uri.host)) return null;
    try {
      return await _load(uri).timeout(timeout);
    } catch (error) {
      AppLog.add('Превью ссылки не получено: $error');
      return null;
    }
  }

  static bool _isLocal(String host) {
    final h = host.toLowerCase();
    return h == 'localhost' ||
        h.endsWith('.local') ||
        RegExp(r'^(127\.|10\.|192\.168\.|169\.254\.|172\.(1[6-9]|2\d|3[01])\.)').hasMatch(h) ||
        h == '::1';
  }

  static Future<LinkPreview?> _load(Uri uri) async {
    final client = http.Client();
    try {
      final request = http.Request('GET', uri)
        ..headers['User-Agent'] = 'Mozilla/5.0 (compatible; ChaWoLinkPreview/1.0)'
        ..headers['Accept'] = 'text/html,application/xhtml+xml';
      final response = await client.send(request);
      final type = response.headers['content-type'] ?? '';
      if (response.statusCode != 200 || !type.contains('html')) return null;

      final bytes = <int>[];
      await for (final chunk in response.stream) {
        bytes.addAll(chunk);
        if (bytes.length >= _maxPage) break;
      }
      final html = utf8.decode(bytes, allowMalformed: true);

      String? meta(String property) {
        final tags = RegExp('<meta\\s[^>]*>', caseSensitive: false).allMatches(html);
        for (final tag in tags) {
          final text = tag.group(0)!;
          final key = RegExp('(?:property|name)\\s*=\\s*["\']([^"\']+)["\']', caseSensitive: false)
              .firstMatch(text)
              ?.group(1)
              ?.toLowerCase();
          if (key != property) continue;
          final content = RegExp('content\\s*=\\s*"([^"]*)"|content\\s*=\\s*\'([^\']*)\'', caseSensitive: false)
              .firstMatch(text);
          final value = content?.group(1) ?? content?.group(2);
          if (value != null && value.trim().isNotEmpty) return _unescape(value.trim());
        }
        return null;
      }

      final title = meta('og:title') ??
          meta('twitter:title') ??
          _unescape(RegExp('<title[^>]*>([^<]*)</title>', caseSensitive: false).firstMatch(html)?.group(1)?.trim() ?? '');
      final description = meta('og:description') ?? meta('description') ?? meta('twitter:description');
      final imageUrl = meta('og:image') ?? meta('twitter:image');

      final preview = LinkPreview(
        url: uri.toString(),
        title: title.isEmpty ? null : _cut(title, 120),
        description: description == null ? null : _cut(description, 200),
        imageB64: imageUrl == null ? null : await _image(client, uri.resolve(imageUrl)),
      );
      return preview.hasContent ? preview : null;
    } finally {
      client.close();
    }
  }

  static Future<String?> _image(http.Client client, Uri uri) async {
    try {
      if (uri.scheme != 'https' && uri.scheme != 'http' || _isLocal(uri.host)) return null;
      final response = await client.get(uri).timeout(const Duration(seconds: 3));
      if (response.statusCode != 200 || response.bodyBytes.length > _maxImage) return null;
      final codec = await ui.instantiateImageCodec(response.bodyBytes, targetWidth: _imageWidth);
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      frame.image.dispose();
      final Uint8List? png = data?.buffer.asUint8List();
      if (png == null) return null;
      final encoded = base64Encode(png);
      return encoded.length > _maxImageB64 ? null : encoded;
    } catch (_) {
      return null;
    }
  }

  static String _cut(String value, int max) =>
      value.length <= max ? value : '${value.substring(0, max).trimRight()}…';

  static String _unescape(String value) => value
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&nbsp;', ' ');
}
