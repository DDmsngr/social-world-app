import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/debug/app_log.dart';
import 'call_models.dart';

/// Системная звонилка (flutter_callkit_incoming): экран входящего поверх
/// блокировки, рингтон, «идёт звонок» в шторке. Последнее заодно держит
/// приложение живым в фоне (служба переднего плана с микрофоном), иначе
/// Android отрезал бы микрофон, как только человек свернёт экран звонка.
///
/// Работает и в фоновом обработчике пушей, где приложения ещё нет, поэтому
/// без Riverpod и без роутера.
abstract final class CallKit {
  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static const _askedKey = 'calls.fullscreen_asked';

  /// Звонилка у получателя гаснет сама чуть позже, чем звонящий сдаётся
  /// (45 с): к этому времени сервер уже пришлёт «пропущенный».
  static const _ringFor = Duration(seconds: 55);

  static CallKitParams _params(CallInfo call) => CallKitParams(
    id: call.id,
    nameCaller: call.peerName,
    appName: 'ChaWo',
    avatar: call.peerAvatarUrl,
    handle: call.video ? 'Видеозвонок ChaWo' : 'Звонок ChaWo',
    type: call.video ? 1 : 0,
    duration: _ringFor.inMilliseconds,
    extra: call.toPush(),
    missedCallNotification: NotificationParams(
      showNotification: true,
      isShowCallback: false,
      subtitle: call.video ? 'Пропущенный видеозвонок' : 'Пропущенный звонок',
    ),
    callingNotification: NotificationParams(
      showNotification: true,
      isShowCallback: true,
      subtitle: call.video ? 'Видеозвонок' : 'Звонок',
      callbackText: 'Завершить',
    ),
    android: const AndroidParams(
      isCustomNotification: true,
      isShowLogo: false,
      ringtonePath: 'system_ringtone_default',
      backgroundColor: '#1A1418',
      actionColor: '#4CAF50',
      textColor: '#FFFFFF',
      incomingCallNotificationChannelName: 'Входящие звонки',
      missedCallNotificationChannelName: 'Пропущенные звонки',
      isShowCallID: false,
      isShowFullLockedScreen: true,
      textAccept: 'Ответить',
      textDecline: 'Отклонить',
    ),
  );

  static Future<void> showIncoming(CallInfo call) async {
    if (!supported) return;
    try {
      await FlutterCallkitIncoming.showCallkitIncoming(_params(call));
    } catch (error) {
      AppLog.add('Звонилка не показалась: $error');
    }
  }

  /// Исходящий: «идёт звонок» в шторке и служба, которая не даёт системе
  /// отнять микрофон в фоне.
  static Future<void> startOutgoing(CallInfo call) async {
    if (!supported) return;
    try {
      await FlutterCallkitIncoming.startCall(_params(call));
    } catch (error) {
      AppLog.add('Звонилка (исходящий): $error');
    }
  }

  static Future<void> connected(String id) async {
    if (!supported) return;
    try {
      await FlutterCallkitIncoming.setCallConnected(id);
    } catch (error) {
      AppLog.add('Звонилка (соединено): $error');
    }
  }

  static Future<void> end(String id) async {
    if (!supported) return;
    try {
      await FlutterCallkitIncoming.endCall(id);
    } catch (error) {
      AppLog.add('Звонилка не погасла: $error');
    }
  }

  static Future<void> showMissed(CallInfo call) async {
    if (!supported) return;
    try {
      await FlutterCallkitIncoming.showMissCallNotification(_params(call));
    } catch (error) {
      AppLog.add('Пропущенный не показался: $error');
    }
  }

  /// Звонок, на который уже ответили в звонилке, а приложение только
  /// запускается: событие «ответил» могло прийти раньше, чем его стали слушать.
  static Future<CallInfo?> acceptedCall() async {
    if (!supported) return null;
    try {
      final calls = await FlutterCallkitIncoming.activeCalls();
      for (final call in calls) {
        if (!call.isAccepted) continue;
        final info = CallInfo.fromPush(Map<String, dynamic>.from(call.extra ?? const {}));
        if (info != null) return info;
      }
    } catch (error) {
      AppLog.add('Активные звонки не прочитались: $error');
    }
    return null;
  }

  /// Разрешения, без которых звонилка не появится поверх блокировки
  /// (Android 14+ спрашивает отдельно про полноэкранные уведомления).
  /// Спрашиваем один раз за установку: запрос открывает системные настройки,
  /// и делать это на каждом запуске было бы назойливо.
  static Future<void> ensurePermissions() async {
    if (!supported) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_askedKey) ?? false) return;
      if (!await FlutterCallkitIncoming.canUseFullScreenIntent()) {
        await prefs.setBool(_askedKey, true);
        await FlutterCallkitIncoming.requestFullIntentPermission();
      }
    } catch (error) {
      AppLog.add('Разрешение звонилки: $error');
    }
  }
}
