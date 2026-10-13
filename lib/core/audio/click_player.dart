import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

import '../debug/app_log.dart';

/// Короткие звуки интерфейса (щелчок отправки и входящего). Каждый раз новый
/// проигрыватель, который сам закрывается: один долгоживущий после пары
/// проигрываний у части телефонов молча переставал играть.
abstract final class ClickPlayer {
  static Future<void> play(String asset, {double volume = 0.8}) async {
    AudioPlayer? player;
    try {
      player = AudioPlayer();
      await player.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            audioFocus: AndroidAudioFocus.none,
            // Громкость медиа. Раньше стоял поток уведомлений (системные звуки
            // на многих телефонах выключены), но и он глохнет при «Не
            // беспокоить» и нулевой громкости уведомлений: щелчки и звук
            // отправки пропадали целиком. Медиа-поток этого не касается.
            usageType: AndroidUsageType.media,
            contentType: AndroidContentType.sonification,
          ),
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.ambient,
            options: const {AVAudioSessionOptions.mixWithOthers},
          ),
        ),
      );
      await player.setReleaseMode(ReleaseMode.release);
      final done = player;
      unawaited(done.onPlayerComplete.first.timeout(const Duration(seconds: 4), onTimeout: () {}).whenComplete(done.dispose));
      await player.play(AssetSource(asset), volume: volume);
    } catch (error) {
      AppLog.add('Звук $asset: $error');
      await player?.dispose();
    }
  }
}
