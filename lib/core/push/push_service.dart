import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/chat/presentation/providers/chat_providers.dart';
import '../../features/notifications/notifications.dart';
import '../audio/incoming_click.dart';
import '../config/env.dart';
import '../debug/app_log.dart';
import '../../features/chat/presentation/chat_looks.dart';
import '../links/deep_links.dart';
import '../router/app_router.dart';

/// Push-уведомления (FCM). Шлёт их сервер (Edge Function `push-send`,
/// миграция 0031); здесь — регистрация токена устройства, показ пуша при
/// открытом приложении и переход по тапу.
///
/// Тап обрабатывается в трёх положениях приложения, как в DDChat: открыто
/// (локальное уведомление), свёрнуто (onMessageOpenedApp) и закрыто
/// (getInitialMessage). Сервис запускается из оболочки вкладок, когда роутер
/// уже есть, поэтому откладывать переход не нужно.
class PushService {
  PushService(this._ref);

  final Ref _ref;
  final _local = FlutterLocalNotificationsPlugin();
  final _subscriptions = <StreamSubscription<Object?>>[];
  bool _started = false;
  bool _localReady = false;
  String? _token;

  /// Открытый сейчас чат: пуши о нём не показываются, человек и так его видит.
  String? activeConversationId;

  static const _messages = AndroidNotificationChannel(
    'messages',
    'Сообщения',
    description: 'Новые сообщения в чатах',
    importance: Importance.high,
  );
  /// «Отправить без звука»: уведомление приходит, но молча и без вибрации.
  /// Звук и вибрация в Android задаются каналом, поэтому нужен отдельный.
  static const _messagesSilent = AndroidNotificationChannel(
    'messages_silent',
    'Сообщения без звука',
    description: 'Сообщения, отправленные без звука',
    importance: Importance.defaultImportance,
    playSound: false,
    enableVibration: false,
  );
  /// Режим чата «только вибрация».
  static const _messagesVibrate = AndroidNotificationChannel(
    'messages_vibrate',
    'Сообщения — только вибрация',
    description: 'Чаты с режимом «только вибрация»',
    importance: Importance.high,
    playSound: false,
    enableVibration: true,
  );
  /// Сообщение, пока приложение открыто: всплывает, но без системного звука —
  /// вместо него играет короткий щелчок [IncomingClick].
  static const _messagesInApp = AndroidNotificationChannel(
    'messages_inapp',
    'Сообщения при открытом приложении',
    description: 'Всплывают без звука, приложение само щёлкает',
    importance: Importance.high,
    playSound: false,
    enableVibration: false,
  );
  static const _activity = AndroidNotificationChannel(
    'activity',
    'Активность',
    description: 'Подписчики, комментарии, события, квесты',
    importance: Importance.high,
  );

  Future<void> start() async {
    if (_started || kIsWeb || !Env.isConfigured) return;
    _started = true;
    try {
      await Firebase.initializeApp();
    } catch (error) {
      // Сборка без google-services.json: пушей нет, остальное работает.
      AppLog.add('Push выключены: $error');
      return;
    }

    try {
      await _local.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@drawable/ic_notification'),
        ),
        onDidReceiveNotificationResponse: (response) =>
            _openPayload(response.payload),
      );
      final android = _local
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await android?.createNotificationChannel(_messages);
      await android?.createNotificationChannel(_messagesSilent);
      await android?.createNotificationChannel(_messagesVibrate);
      await android?.createNotificationChannel(_messagesInApp);
      // Свой звук чата — отдельный канал со звуком из res/raw. Сервер выбирает канал
      // по настройке получателя (push-send), так что система сама играет нужный звук.
      for (final sound in chatSounds) {
        await android?.createNotificationChannel(
          AndroidNotificationChannel(
            'messages_${sound.id}',
            'Сообщения — ${sound.label}',
            description: 'Чаты со звуком «${sound.label}»',
            importance: Importance.high,
            sound: RawResourceAndroidNotificationSound(sound.id),
          ),
        );
      }
      await android?.createNotificationChannel(_activity);
      _localReady = true;

      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();

      _subscriptions
        ..add(FirebaseMessaging.onMessage.listen(_onForeground))
        ..add(FirebaseMessaging.onMessageOpenedApp.listen((m) => _open(m.data)))
        ..add(messaging.onTokenRefresh.listen(_register));

      final token = await messaging.getToken();
      if (token != null) await _register(token);

      final initial = await messaging.getInitialMessage();
      if (initial != null) {
        _open(initial.data);
      } else {
        // Запуск тапом по уведомлению, которое показали мы сами.
        final launch = await _local.getNotificationAppLaunchDetails();
        if (launch?.didNotificationLaunchApp ?? false) {
          _openPayload(launch!.notificationResponse?.payload);
        }
      }
    } catch (error) {
      AppLog.add('Push не запустились: $error');
    }
  }

  /// Перед выходом из аккаунта: токен отвязывается от человека, иначе его
  /// пуши продолжили бы приходить на этот телефон.
  Future<void> stop() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    final token = _token;
    _token = null;
    _started = false;
    if (token == null) return;
    try {
      await Supabase.instance.client.rpc(
        'unregister_push_token',
        params: {'in_token': token},
      );
      await FirebaseMessaging.instance.deleteToken();
    } catch (error) {
      AppLog.add('Токен пушей не отвязался: $error');
    }
  }

  /// Убрать из шторки уведомления открытого чата.
  Future<void> clearConversation(String conversationId) async {
    if (!_localReady) return;
    try {
      await _local.cancel(id: 0, tag: conversationId);
    } catch (error) {
      AppLog.add('Не удалось убрать уведомление: $error');
    }
  }

  Future<void> _register(String token) async {
    _token = token;
    try {
      await Supabase.instance.client.rpc(
        'register_push_token',
        params: {'in_token': token, 'in_platform': 'android'},
      );
    } catch (error) {
      AppLog.add('Токен пушей не сохранился: $error');
    }
  }

  void _onForeground(RemoteMessage message) {
    final data = message.data;
    final isMessage = data['type'] == 'message';
    if (isMessage) {
      _ref.invalidate(conversationsProvider);
      if (data['conversation_id'] == activeConversationId) return;
    } else {
      _ref.read(notificationsProvider.notifier).refreshQuietly();
    }

    final notification = message.notification;
    if (notification == null || !_localReady) return;
    final mode = !isMessage
        ? _activity
        : switch (data['channel']) {
            'messages_silent' => _messagesSilent,
            'messages_vibrate' => _messagesVibrate,
            _ => data['silent'] == '1' ? _messagesSilent : _messages,
          };
    // Приложение открыто, а сообщение (или реакция) из другого чата: короткий
    // щелчок вместо звука уведомления, режим чата при этом соблюдается.
    var channel = mode;
    if (identical(mode, _messages)) {
      IncomingClick.play();
      channel = _messagesInApp;
    } else if (identical(mode, _messagesVibrate)) {
      HapticFeedback.mediumImpact();
    }
    // id 0 + tag — так же, как пуш, нарисованный системой в фоне: новое
    // уведомление того же чата заменяет прошлое, а не копит стопку.
    _local.show(
      id: 0,
      title: notification.title,
      body: notification.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: channel.importance,
          priority: channel.playSound ? Priority.high : Priority.defaultPriority,
          playSound: channel.playSound,
          enableVibration: channel.enableVibration,
          icon: '@drawable/ic_notification',
          tag: data['conversation_id'] ?? data['notification_id'],
        ),
      ),
      payload: jsonEncode(data),
    );
  }

  void _openPayload(String? payload) {
    if (payload == null || payload.isEmpty) return;
    try {
      _open(Map<String, dynamic>.from(jsonDecode(payload) as Map));
    } catch (error) {
      AppLog.add('Не удалось открыть уведомление: $error');
    }
  }

  void _open(Map<String, dynamic> data) {
    final router = _ref.read(routerProvider);
    switch (data['type']) {
      case 'message':
        final id = data['conversation_id'] as String?;
        if (id == null) return;
        if (data['channel'] == '1') {
          router.push(Routes.channel(id));
        } else {
          router.push('${Routes.chats}/$id', extra: data['title'] as String?);
        }
      case 'notification':
        final target = LinkTarget.fromSegment(data['target_type'] as String? ?? '');
        final id = data['target_id'] as String?;
        if (target == null || id == null || id.isEmpty) {
          router.push(Routes.notifications);
        } else {
          router.push(DeepLinks.locationFor(target, id));
        }
    }
  }

  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
  }
}

final pushServiceProvider = Provider<PushService>((ref) {
  ref.keepAlive();
  final service = PushService(ref);
  ref.onDispose(service.dispose);
  return service;
});
