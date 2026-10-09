import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../debug/app_log.dart';

/// Короткий звук колокольчика, когда в открытом приложении приходит
/// уведомление. Включён по умолчанию, выключается в настройках уведомлений.
/// Играет по потоку уведомлений и не забирает звуковой фокус: музыка не
/// затихает.
abstract final class BellSound {
  static const _key = 'bell_sound_enabled';
  static AudioPlayer? _player;
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
      AppLog.add('Звук колокольчика не сохранился: $error');
    }
  }

  static Future<void> play({bool force = false}) async {
    try {
      if (!force && !await isEnabled()) return;
      final player = _player ??= AudioPlayer()
        ..setAudioContext(
          AudioContext(
            android: const AudioContextAndroid(
              audioFocus: AndroidAudioFocus.none,
              usageType: AndroidUsageType.notificationCommunicationInstant,
              contentType: AndroidContentType.sonification,
            ),
            iOS: AudioContextIOS(
              category: AVAudioSessionCategory.ambient,
              options: const {AVAudioSessionOptions.mixWithOthers},
            ),
          ),
        )
        ..setReleaseMode(ReleaseMode.stop);
      await player.stop();
      await player.play(AssetSource('sounds/drop.wav'), volume: 0.8);
    } catch (error) {
      AppLog.add('Звук колокольчика: $error');
    }
  }
}
