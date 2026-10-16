import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

import '../debug/app_log.dart';

/// Освобождает проигрыватель, когда звук доиграл, поток закрылся или прошло
/// [timeout]. `.then<void>` нужен, чтобы onTimeout мог вернуть пустоту: без
/// него `() {}` не подходил по типу, и каждый вызов падал ДО звука (журнал
/// 15.10: «type '() => Null' is not a subtype … onTimeout»).
Future<void> releaseWhenDone(
  Stream<Object?> done,
  FutureOr<void> Function() dispose, {
  Duration timeout = const Duration(seconds: 4),
}) => done.first
    .then<void>((_) {}, onError: (Object _) {})
    .timeout(timeout, onTimeout: () {})
    .whenComplete(dispose);

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
      unawaited(releaseWhenDone(done.onPlayerComplete, done.dispose));
      await player.play(AssetSource(asset), volume: volume);
    } catch (error) {
      AppLog.add('Звук $asset: $error');
      await player?.dispose();
    }
  }
}
