import '../debug/app_log.dart';
import 'click_player.dart';

/// Короткий щелчок, когда человек в приложении, но не в том чате, куда
/// пришло сообщение или реакция. Отличается от звука уведомления: тот играет,
/// когда приложение свёрнуто. Звуковой фокус не забирает — музыка не затихает.
abstract final class IncomingClick {
  static DateTime _last = DateTime(0);

  static Future<void> play() async {
    // Пачка сообщений подряд — один щелчок, а не трещотка.
    final now = DateTime.now();
    if (now.difference(_last) < const Duration(milliseconds: 700)) return;
    _last = now;
    try {
      await ClickPlayer.play('sounds/click.wav', volume: 0.9);
    } catch (error) {
      AppLog.add('Щелчок входящего: $error');
    }
  }
}
