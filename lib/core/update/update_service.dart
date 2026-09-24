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

  static const _manifestPath =
      'storage/v1/object/public/app-releases/manifest.json';

  Future<UpdateInfo?> fetchManifest() async {
    final uri = Uri.parse('${Env.supabaseUrl}/$_manifestPath');
    final response = await _client.get(uri).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) return null;
    return UpdateInfo.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// Качает APK в [destination], отдавая прогресс 0..1. Пишет потоково —
  /// файл обновления десятки мегабайт, целиком в память грузить незачем.
  ///
  /// Умеет докачку: если [destination] уже лежит частично (прошлая попытка
  /// оборвалась на мобильной сети), просим у сервера только остаток
  /// (`Range: bytes=N-`). Раньше любой обрыв означал «с нуля», а файл в 175 МБ
  /// на мобильной сети доходит не всегда. Сервер Range не понял (ответил 200,
  /// а не 206) — тихо качаем заново.
  Stream<double> downloadTo(String url, File destination) async* {
    var have = destination.existsSync() ? destination.lengthSync() : 0;

    final request = http.Request('GET', Uri.parse(url));
    if (have > 0) request.headers['Range'] = 'bytes=$have-';
    final response = await _client.send(request);

    // 416: просили с позиции за концом файла — значит частичный файл битый
    // или уже целый, но мы этого не знаем. Надёжнее начать заново.
    if (response.statusCode == 416) {
      await response.stream.drain<void>();
      await destination.delete();
      yield* downloadTo(url, destination);
      return;
    }

    final resumed = response.statusCode == 206;
    if (!resumed && response.statusCode != 200) {
      throw Exception('Не удалось скачать обновление (${response.statusCode})');
    }
    if (!resumed) have = 0;

    // У 206 contentLength — размер остатка, а не всего файла.
    final expected = response.contentLength == null
        ? 0
        : have + response.contentLength!;
    var received = have;
    final sink = destination.openWrite(
      mode: resumed ? FileMode.append : FileMode.write,
    );
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (expected > 0) yield received / expected;
      }
    } finally {
      await sink.close();
    }

    // Обрыв иногда выглядит как обычное окончание потока: пришло меньше, чем
    // обещал сервер. Такой файл установщик отвергнет — лучше упасть здесь и
    // дать контроллеру докачать.
    if (expected > 0 && received < expected) {
      throw Exception('Скачано $received из $expected байт');
    }
  }
}
