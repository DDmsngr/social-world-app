import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/env.dart';
import 'call_kit.dart';
import 'call_models.dart';

/// Пуш, пришедший, когда приложение свёрнуто или закрыто. Работает в отдельном
/// фоновом isolate: ни роутера, ни Riverpod здесь нет. Остальные пуши
/// (сообщения, уведомления) рисует система сама, их не трогаем.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  final data = message.data;
  switch (data['type']) {
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

bool _supabaseReady = false;

Future<void> _ensureSupabase() async {
  if (_supabaseReady) return;
  await Env.load();
  if (!Env.isConfigured) return;
  await Supabase.initialize(url: Env.supabaseUrl, publishableKey: Env.supabaseAnonKey);
  _supabaseReady = true;
}
