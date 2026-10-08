import 'package:appmetrica_plugin/appmetrica_plugin.dart';
import 'package:flutter/foundation.dart';

import '../debug/app_log.dart';

/// Яндекс AppMetrica. Ключ приложения не секретный: по нему данные только
/// пишутся. Личного не отправляем — ни имён, ни текстов, ни идентификаторов
/// людей, только названия событий.
class Analytics {
  Analytics._();

  static const _apiKey = 'cfe8e63a-ebbe-4b67-b71f-082cfe13cf49';
  static var _ready = false;

  static Future<void> init() async {
    if (kIsWeb || _ready) return;
    try {
      await AppMetrica.activate(AppMetricaConfig(_apiKey));
      _ready = true;
    } catch (error) {
      AppLog.add('AppMetrica: $error');
    }
  }

  static void event(String name) {
    if (!_ready) return;
    AppMetrica.reportEvent(name).catchError((Object error) {
      AppLog.add('AppMetrica событие $name: $error');
    });
  }
}
