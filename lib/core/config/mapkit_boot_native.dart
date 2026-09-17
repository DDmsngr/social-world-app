import 'package:yandex_maps_mapkit/init.dart' as ymk_init;

import '../debug/app_log.dart';

abstract final class MapkitBoot {
  /// Виден в dev-панели: без него молчаливо пустая карта неотличима от
  /// отсутствующего ключа.
  static String status = 'not_started';

  static bool get isReady => status.startsWith('ok');

  static Future<void> init(String apiKey) async {
    if (apiKey.isEmpty) {
      status = 'no_key';
      AppLog.add('MapkitBoot: ключ пуст (.env/секрет CI не заполнен)');
      return;
    }
    try {
      await ymk_init.initMapkit(apiKey: apiKey);
      // initMapkit не проверяет ключ — сеть/сервер Яндекса могут отклонить
      // его позже при загрузке тайлов, и это никак не всплывёт здесь.
      // Префикс ключа в статусе — чтобы при следующем баг-репорте сверить,
      // какой именно ключ ушёл в сборку, не печатая секрет целиком.
      final prefix = apiKey.substring(0, apiKey.length < 8 ? apiKey.length : 8);
      status = 'ok:$prefix';
      AppLog.add('MapkitBoot: initMapkit ok, ключ $prefix…');
    } catch (e) {
      status = 'error: $e';
      AppLog.add('MapkitBoot: initMapkit упал — $e');
    }
  }
}
