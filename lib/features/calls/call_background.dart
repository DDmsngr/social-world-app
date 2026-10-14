import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/env.dart';
import '../../core/push/push_preview.dart';
import 'call_kit.dart';
import 'call_models.dart';

/// Пуш, пришедший, когда приложение свёрнуто или закрыто. Работает в отдельном
/// фоновом isolate: ни роутера, ни Riverpod здесь нет. Уведомления о
/// сообщениях рисует система («Новое сообщение» в личных чатах); текст личного
/// сообщения телефон расшифровывает здесь и подменяет уведомление.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  final data = message.data;
  switch (data['type']) {
    case 'message':
      await _showDirectText(data);
    case 'call':
      final info = CallInfo.fromPush(data);
      if (info != null) await CallKit.showIncoming(info);
    case 'call_update':
      final id = data['call_id'];
      if (id is! String) return;
      await CallKit.end(id);
      if (data['status'] == 'missed' || data['status'] == 'cancelled') {
        final info = CallInfo.fromPush(data);
        if (info != null) await CallKit.showMissed(info);
      }
  }
}

/// «Отклонить» в звонилке, когда приложение закрыто: звонящий должен узнать
/// сразу, а не ждать 45 секунд гудков. Сессия входа лежит на телефоне, её
/// подхватывает Supabase и здесь.
@pragma('vm:entry-point')
Future<void> callkitBackgroundHandler(CallEvent event) async {
  if (event is! CallEventActionCallDecline) return;
  try {
    WidgetsFlutterBinding.ensureInitialized();
    await _ensureSupabase();
    await Supabase.instance.client.rpc(
      'end_call',
      params: {'in_call': event.callKitParams.id, 'in_reason': null},
    );
  } catch (error) {
    debugPrint('Отклонение звонка в фоне не дошло: $error');
  }
}

/// Подменить «Новое сообщение» на текст: тот же id 0 и tag, что у пуша,
/// нарисованного системой, поэтому уведомление заменяется, а не копится.
/// Без звука: звук уже сыграл системный пуш. Любой сбой — остаётся системное.
Future<void> _showDirectText(Map<String, dynamic> data) async {
  if (data['e2e'] != '1') return;
  try {
    WidgetsFlutterBinding.ensureInitialized();
    await _ensureSupabase();
    if (!_supabaseReady) return;
    final text = await directMessagePreview(data);
    if (text == null) return;
    final local = FlutterLocalNotificationsPlugin();
    await local.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@drawable/ic_notification'),
      ),
    );
    final channel = data['channel'] as String? ?? 'messages';
    await local.show(
      id: 0,
      title: data['title'] as String?,
      body: text,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channel,
          'Сообщения',
          importance: Importance.high,
          priority: Priority.high,
          silent: true,
          onlyAlertOnce: true,
          icon: '@drawable/ic_notification',
          tag: data['conversation_id'] as String?,
          styleInformation: BigTextStyleInformation(text),
        ),
      ),
      payload: jsonEncode(data),
    );
  } catch (error) {
    debugPrint('Текст сообщения для шторки не получен: $error');
  }
}

bool _supabaseReady = false;

Future<void> _ensureSupabase() async {
  if (_supabaseReady) return;
  await Env.load();
  if (!Env.isConfigured) return;
  await Supabase.initialize(url: Env.supabaseUrl, publishableKey: Env.supabaseAnonKey);
  _supabaseReady = true;
}
