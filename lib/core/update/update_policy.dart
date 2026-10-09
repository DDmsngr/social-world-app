import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Когда качать обновление без нажатия. По умолчанию — только по Wi-Fi:
/// APK весит больше сотни мегабайт, и тратить на него мобильный трафик
/// человек должен разрешить сам (переключатель в настройках).
class UpdatePolicy {
  static const prefsMobileKey = 'update.auto_mobile';
  static const _channel = MethodChannel('chawo/device');

  static Future<bool> allowMobile() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(prefsMobileKey) ?? false;
  }

  static Future<void> setAllowMobile(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefsMobileKey, value);
  }

  static Future<bool> onWifi() async {
    try {
      return await _channel.invokeMethod<bool>('onWifi') ?? false;
    } catch (_) {
      // Не узнали сеть — считаем мобильной: лучше подождать, чем потратить
      // чужой трафик.
      return false;
    }
  }

  static bool shouldAutoDownload({required bool onWifi, required bool allowMobile}) =>
      onWifi || allowMobile;

  /// Старые скачанные APK, которые пора удалить: всё `social-world-*.apk`,
  /// кроме файла, который ещё ждёт установки.
  static List<String> staleApks(Iterable<String> paths, {String? keep}) => [
    for (final path in paths)
      if (path != keep && RegExp(r'social-world-\d+(-arm64)?\.apk$').hasMatch(path)) path,
  ];
}
