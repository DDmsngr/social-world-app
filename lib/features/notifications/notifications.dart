import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/env.dart';
import '../../core/debug/app_log.dart';
import '../../core/links/deep_links.dart';
import '../auth/presentation/providers/auth_providers.dart';

/// Совпадает с `notifications.kind` в базе. Типов немного намеренно: каждый
/// ведёт на конкретный объект, а не в общий «поток событий».
enum NotificationKind {
  follow,
  comment,
  reply,
  reaction,
  eventJoin('event_join'),
  eventChanged('event_changed'),
  eventCancelled('event_cancelled'),
  message,
  questRequest('quest_request'),
  questJoin('quest_join'),
  questApproved('quest_approved'),
  questRejected('quest_rejected'),
  questRemoved('quest_removed'),
  questCancelled('quest_cancelled'),
  needResponse('need_response');

  const NotificationKind([this._wire]);

  final String? _wire;

  String get wire => _wire ?? name;

  static NotificationKind? parse(dynamic raw) {
    for (final kind in values) {
      if (kind.wire == raw) return kind;
    }
    return null;
  }
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.target,
    required this.targetId,
    required this.createdAt,
    this.actorId,
    this.actorName,
    this.actorAvatarUrl,
    this.title,
    this.readAt,
  });

  final String id;
  final NotificationKind kind;
  final String? actorId;
  final String? actorName;
  final String? actorAvatarUrl;
  final LinkTarget target;
  final String targetId;
  final String? title;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get isUnread => readAt == null;

  String get location => DeepLinks.locationFor(target, targetId);

  /// Готовая строка: «Алина подписалась на вас».
  String get text {
    final who = actorName ?? 'Кто-то';
    final about = title == null || title!.isEmpty ? '' : ': «$title»';
    return switch (kind) {
      NotificationKind.follow => '$who — новый подписчик',
      NotificationKind.comment => '$who: новый комментарий к вашей публикации$about',
      NotificationKind.reply => '$who: ответ на ваш комментарий$about',
      NotificationKind.reaction => '$who: реакция на вашу публикацию',
      NotificationKind.eventJoin => '$who участвует в вашем событии$about',
      NotificationKind.eventChanged => 'Событие изменилось$about',
      NotificationKind.eventCancelled => 'Событие отменено$about',
      NotificationKind.message => '$who: новое сообщение',
      NotificationKind.questRequest => '$who хочет в ваш квест$about',
      NotificationKind.questJoin => '$who теперь в вашем квесте$about',
      NotificationKind.questApproved => 'Вас приняли в квест$about',
      NotificationKind.questRejected => 'Заявку в квест не приняли$about',
      NotificationKind.questRemoved => 'Вас исключили из квеста$about',
      NotificationKind.questCancelled => 'Квест отменён$about',
      NotificationKind.needResponse => '$who готов помочь с вашей просьбой$about',
    };
  }

  AppNotification asRead() => AppNotification(
    id: id,
    kind: kind,
    actorId: actorId,
    actorName: actorName,
    actorAvatarUrl: actorAvatarUrl,
    target: target,
    targetId: targetId,
    title: title,
    createdAt: createdAt,
    readAt: readAt ?? DateTime.now(),
  );
}

abstract interface class NotificationsRepository {
  Future<List<AppNotification>> load();

  /// Без [ids] — все непрочитанные.
  Future<void> markRead([List<String>? ids]);
}

class SupabaseNotificationsRepository implements NotificationsRepository {
  SupabaseNotificationsRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<AppNotification>> load() async {
    final rows = await _client.rpc(
      'my_notifications',
      params: {'in_limit': 50},
    ) as List<dynamic>;

    return [
      for (final raw in rows) ?_parse(raw as Map<String, dynamic>),
    ];
  }

  AppNotification? _parse(Map<String, dynamic> row) {
    final kind = NotificationKind.parse(row['kind']);
    final target = LinkTarget.fromSegment(row['target_type'] as String? ?? '');
    if (kind == null || target == null) return null;
    return AppNotification(
      id: row['id'] as String,
      kind: kind,
      actorId: row['actor_id'] as String?,
      actorName: row['actor_name'] as String?,
      actorAvatarUrl: row['actor_avatar'] as String?,
      target: target,
      targetId: row['target_id'] as String,
      title: row['title'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
      readAt: row['read_at'] is String
          ? DateTime.parse(row['read_at'] as String)
          : null,
    );
  }

  @override
  Future<void> markRead([List<String>? ids]) =>
      _client.rpc('mark_notifications_read', params: {'in_ids': ids});
}

class LocalNotificationsRepository implements NotificationsRepository {
  final _items = <AppNotification>[
    AppNotification(
      id: 'n1',
      kind: NotificationKind.reaction,
      actorId: 'person-3',
      actorName: 'Саша',
      target: LinkTarget.post,
      targetId: 'seed-1',
      createdAt: DateTime.now().subtract(const Duration(minutes: 12)),
    ),
    AppNotification(
      id: 'n2',
      kind: NotificationKind.follow,
      actorId: 'person-6',
      actorName: 'Ника',
      target: LinkTarget.profile,
      targetId: 'person-6',
      createdAt: DateTime.now().subtract(const Duration(hours: 3)),
    ),
  ];

  @override
  Future<List<AppNotification>> load() async => List.of(_items);

  @override
  Future<void> markRead([List<String>? ids]) async {
    for (var i = 0; i < _items.length; i++) {
      if (ids == null || ids.contains(_items[i].id)) {
        _items[i] = _items[i].asRead();
      }
    }
  }
}

final notificationsRepositoryProvider = Provider<NotificationsRepository>((ref) {
  ref.keepAlive();
  if (!Env.isConfigured) return LocalNotificationsRepository();
  return SupabaseNotificationsRepository(Supabase.instance.client);
});

class NotificationsController extends AsyncNotifier<List<AppNotification>> {
  @override
  Future<List<AppNotification>> build() async {
    ref.keepAlive();
    if (ref.watch(currentUserProvider) == null) return const [];
    return ref.watch(notificationsRepositoryProvider).load();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(notificationsRepositoryProvider).load(),
    );
  }

  /// Фоновое обновление счётчика: молча, без мигания экрана и без ошибки —
  /// значок на колокольчике не стоит того, чтобы тревожить человека.
  Future<void> refreshQuietly() async {
    if (ref.read(currentUserProvider) == null) return;
    try {
      final fresh = await ref.read(notificationsRepositoryProvider).load();
      state = AsyncData(fresh);
    } catch (error) {
      AppLog.add('Уведомления не обновились: $error');
    }
  }

  Future<void> markRead(AppNotification item) async {
    if (!item.isUnread) return;
    state = AsyncData([
      for (final n in state.value ?? const <AppNotification>[])
        if (n.id == item.id) n.asRead() else n,
    ]);
    try {
      await ref.read(notificationsRepositoryProvider).markRead([item.id]);
    } catch (error) {
      AppLog.add('Не удалось отметить прочитанным: $error');
    }
  }

  Future<void> markAllRead() async {
    state = AsyncData([
      for (final n in state.value ?? const <AppNotification>[]) n.asRead(),
    ]);
    try {
      await ref.read(notificationsRepositoryProvider).markRead();
    } catch (error) {
      AppLog.add('Не удалось отметить прочитанными: $error');
    }
  }
}

final notificationsProvider =
    AsyncNotifierProvider<NotificationsController, List<AppNotification>>(
      NotificationsController.new,
    );

final unreadNotificationsProvider = Provider<int>((ref) {
  final items = ref.watch(notificationsProvider).value ?? const [];
  return items.where((item) => item.isUnread).length;
});
