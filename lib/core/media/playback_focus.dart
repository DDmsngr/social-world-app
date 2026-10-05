import 'package:video_player/video_player.dart';

/// Звук одновременно только у одного видео: запуск нового ставит на паузу
/// то, что играло до него — в ленте, статье или где угодно ещё.
abstract final class PlaybackFocus {
  static VideoPlayerController? _current;

  /// Вызывать перед `play()`.
  static void claim(VideoPlayerController controller) {
    final previous = _current;
    if (previous != null && previous != controller && previous.value.isPlaying) {
      previous.pause();
    }
    _current = controller;
  }

  /// Вызывать в `dispose()`.
  static void release(VideoPlayerController controller) {
    if (_current == controller) _current = null;
  }
}
