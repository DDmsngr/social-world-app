import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/env.dart';
import 'update_info.dart';

/// Обращения к бакету `app-releases`: манифест версии и сам APK.
///
/// Бакет публичный на чтение, поэтому обычный GET без токена — ключ
/// приложения (anon) тут вообще не нужен, только базовый URL self-hosted
/// Supabase.
class UpdateService {
  UpdateService(this._client);

  final http.Client _client;

  static const _manifestPath = 'storage/v1/object/public/app-releases/manifest.json';

  Future<UpdateInfo?> fetchManifest() async {
    final uri = Uri.parse('${Env.supabaseUrl}/$_manifestPath');
    final response = await _client.get(uri).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) return null;
    return UpdateInfo.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// Качает APK в [destination], отдавая прогресс 0..1. Пишет потоково —
  /// файл обновления обычно десятки мегабайт, целиком в память грузить незачем.
  Stream<double> downloadTo(String url, File destination) async* {
    final request = http.Request('GET', Uri.parse(url));
    final response = await _client.send(request);
    if (response.statusCode != 200) {
      throw Exception('Не удалось скачать обновление (${response.statusCode})');
    }

    final total = response.contentLength ?? 0;
    var received = 0;
    final sink = destination.openWrite();
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) yield received / total;
      }
    } finally {
      await sink.close();
    }
  }
}
