import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:social_world/core/update/update_service.dart';

// Докачка обновления. APK в 175 МБ на мобильной сети обрывается, и раньше
// любой обрыв означал «качай с нуля». Тесты держат договорённость с сервером:
// частичный файл → просим остаток (Range), понял (206) → дописываем, не понял
// (200) → тихо качаем заново.
void main() {
  late Directory dir;
  late File file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('upd_test_');
    file = File('${dir.path}/app.apk');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  final full = List<int>.generate(1000, (i) => i % 251);

  Future<double> run(UpdateService service) async {
    var last = 0.0;
    await for (final p in service.downloadTo('https://x/app.apk', file)) {
      last = p;
    }
    return last;
  }

  test('качает с нуля и отдаёт прогресс до 1', () async {
    final service = UpdateService(
      MockClient.streaming((request, _) async {
        expect(request.headers.containsKey('range'), isFalse);
        return http.StreamedResponse(
          Stream.value(full),
          200,
          contentLength: full.length,
        );
      }),
    );

    expect(await run(service), 1.0);
    expect(file.readAsBytesSync(), full);
  });

  test('есть частичный файл — просит остаток и дописывает', () async {
    file.writeAsBytesSync(full.sublist(0, 400));
    String? range;
    final service = UpdateService(
      MockClient.streaming((request, _) async {
        range = request.headers['range'];
        return http.StreamedResponse(
          Stream.value(full.sublist(400)),
          206,
          contentLength: 600, // у 206 это размер ОСТАТКА
        );
      }),
    );

    expect(await run(service), 1.0);
    expect(range, 'bytes=400-');
    expect(
      file.readAsBytesSync(),
      full,
      reason: 'файл должен быть целым, без дыр и дублей',
    );
  });

  test(
    'сервер не понял Range (200) — качаем заново, а не клеим к старому',
    () async {
      file.writeAsBytesSync(List.filled(400, 7));
      final service = UpdateService(
        MockClient.streaming((request, _) async {
          return http.StreamedResponse(
            Stream.value(full),
            200,
            contentLength: full.length,
          );
        }),
      );

      await run(service);
      expect(file.readAsBytesSync(), full);
    },
  );

  test('416 — частичный файл битый, начинаем заново', () async {
    file.writeAsBytesSync(List.filled(5000, 1)); // больше, чем весь файл
    var calls = 0;
    final service = UpdateService(
      MockClient.streaming((request, _) async {
        calls++;
        if (request.headers.containsKey('range')) {
          return http.StreamedResponse(const Stream.empty(), 416);
        }
        return http.StreamedResponse(
          Stream.value(full),
          200,
          contentLength: full.length,
        );
      }),
    );

    await run(service);
    expect(calls, 2);
    expect(file.readAsBytesSync(), full);
  });

  test('оборванный поток не выдают за успех', () async {
    final service = UpdateService(
      MockClient.streaming((request, _) async {
        // Обещали 1000 байт, пришло 300, поток закрылся «штатно».
        return http.StreamedResponse(
          Stream.value(full.sublist(0, 300)),
          200,
          contentLength: 1000,
        );
      }),
    );

    await expectLater(run(service), throwsException);
    expect(
      file.lengthSync(),
      300,
      reason: 'обрывок остаётся на диске для докачки',
    );
  });

  test('после обрыва вторая попытка докачивает и файл выходит целым', () async {
    final attempts = <String?>[];
    final service = UpdateService(
      MockClient.streaming((request, _) async {
        attempts.add(request.headers['range']);
        if (attempts.length == 1) {
          return http.StreamedResponse(
            Stream.value(full.sublist(0, 300)),
            200,
            contentLength: 1000,
          );
        }
        return http.StreamedResponse(
          Stream.value(full.sublist(300)),
          206,
          contentLength: 700,
        );
      }),
    );

    await expectLater(run(service), throwsException);
    await run(service);

    expect(attempts, [null, 'bytes=300-']);
    expect(file.readAsBytesSync(), full);
  });

  test('ошибка сервера — исключение, а не тихая пустышка', () async {
    final service = UpdateService(
      MockClient.streaming((request, _) async {
        return http.StreamedResponse(const Stream.empty(), 500);
      }),
    );
    await expectLater(run(service), throwsException);
  });
}
