import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:social_world/core/network/app_http_client.dart';

void main() {
  late HttpServer server;
  late Uri base;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = Uri.parse('http://127.0.0.1:${server.port}');
    server.listen((request) async {
      // «Зависший» ответ: соединение есть, ответа нет.
      if (request.uri.path.contains('hang')) return;
      request.response.write('ok');
      await request.response.close();
    });
  });

  tearDown(() => server.close(force: true));

  test('ответ не пришёл — ошибка по таймауту, а не вечное ожидание; следующий запрос проходит', () async {
    final client = AppHttpClient(responseTimeout: const Duration(milliseconds: 300));
    addTearDown(client.close);
    await expectLater(client.get(base.replace(path: '/rest/v1/hang')), throwsA(isA<TimeoutException>()));
    final next = await client.get(base.replace(path: '/rest/v1/ok'));
    expect(next.body, 'ok');
  });

  test('файлы (storage) без предела по времени ответа', () async {
    final client = AppHttpClient(responseTimeout: const Duration(milliseconds: 100));
    addTearDown(client.close);
    final pending = client.get(base.replace(path: '/storage/v1/hang'));
    final result = await Future.any<Object>([
      pending.then<Object>((r) => r),
      Future<Object>.delayed(const Duration(milliseconds: 500), () => 'ещё ждём'),
    ]);
    expect(result, 'ещё ждём');
    pending.ignore();
  });

  test('обычный ответ проходит как есть', () async {
    final client = AppHttpClient();
    addTearDown(client.close);
    final response = await client.send(http.Request('GET', base.replace(path: '/auth/v1/ok')));
    expect(response.statusCode, 200);
  });
}
