import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../debug/app_log.dart';

/// HTTP-клиент приложения для Supabase.
///
/// После смены сети (Wi-Fi ↔ мобильный, сон телефона) старое соединение из
/// пула бывает «мёртвым»: запрос уходит в него и висит без ответа и без
/// ошибки. Так у Левона 14.10 крутились загрузки на всех вкладках, пока он не
/// перезапустил приложение, хотя сервер отвечал.
///
/// Поэтому: соединение не держим простаивающим дольше 15 с, на установку даём
/// 10 с, а ответ на обычные запросы (база, вход, функции) ждём не дольше 25 с.
/// Не дождались — пул выбрасываем целиком, следующий запрос пойдёт по новому
/// соединению, а экран получит ошибку и покажет «Повторить» вместо вечного
/// спиннера. Файлы (storage) без предела: большое видео грузится дольше.
class AppHttpClient extends http.BaseClient {
  AppHttpClient({this.responseTimeout = const Duration(seconds: 25)}) : _inner = _fresh();

  final Duration responseTimeout;
  http.Client _inner;

  static http.Client _fresh() => IOClient(
    HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..idleTimeout = const Duration(seconds: 15),
  );

  static bool _limited(Uri url) => !url.path.contains('/storage/v1/');

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final client = _inner;
    if (!_limited(request.url)) return client.send(request);
    try {
      return await client.send(request).timeout(responseTimeout);
    } on TimeoutException {
      AppLog.add('Сервер не ответил за ${responseTimeout.inSeconds} с: ${request.method} ${request.url.path} — пересоздаём соединения');
      _reset(client);
      rethrow;
    } on SocketException {
      _reset(client);
      rethrow;
    }
  }

  void _reset(http.Client broken) {
    if (!identical(_inner, broken)) return;
    _inner = _fresh();
    broken.close();
  }

  @override
  void close() => _inner.close();
}
