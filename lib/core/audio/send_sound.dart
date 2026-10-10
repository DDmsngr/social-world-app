import 'package:shared_preferences/shared_preferences.dart';

import '../debug/app_log.dart';
import 'click_player.dart';

/// Короткий звук при отправке сообщения. Включён по умолчанию, выключается
/// в настройках. Играет как системный «щелчок» интерфейса: не перехватывает
/// звуковой фокус (музыка не затихает) и подчиняется громкости телефона.
abstract final class SendSound {
  static const _key = 'send_sound_enabled';
  static bool? _enabled;

  static Future<bool> isEnabled() async {
    if (_enabled != null) return _enabled!;
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_key) ?? true;
    } catch (_) {
      _enabled = true;
    }
    return _enabled!;
  }

  static Future<void> setEnabled(bool value) async {
    _enabled = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, value);
    } catch (error) {
      AppLog.add('Звук отправки не сохранился: $error');
    }
  }

  static Future<void> play() async {
    try {
      if (!await isEnabled()) return;
      await ClickPlayer.play('sounds/send.wav', volume: 0.7);
    } catch (error) {
      // Звук — приятная мелочь: сбой проигрывателя не должен мешать отправке.
      AppLog.add('Звук отправки: $error');
    }
  }
}
