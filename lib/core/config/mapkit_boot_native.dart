import 'package:yandex_maps_mapkit/init.dart' as ymk_init;

abstract final class MapkitBoot {
  /// Виден в dev-панели: без него молчаливо пустая карта неотличима от
  /// отсутствующего ключа.
  static String status = 'not_started';

  static bool get isReady => status == 'ok';

  static Future<void> init(String apiKey) async {
    if (apiKey.isEmpty) {
      status = 'no_key';
      return;
    }
    try {
      await ymk_init.initMapkit(apiKey: apiKey);
      status = 'ok';
    } catch (e) {
      status = 'error: $e';
    }
  }
}
