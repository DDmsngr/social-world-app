import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/env.dart';
import '../../core/debug/app_log.dart';
import '../auth/presentation/providers/auth_providers.dart';

/// Категория уведомлений в настройках. [key] совпадает с ключом в
/// `notification_prefs.settings` (миграция 0070). Звонки сюда не входят: они
/// приходят всегда.
enum NotificationCategory {
  messages(
    'messages',
    'Сообщения',
    'Личные чаты, группы и каналы',
    defaultOn: true,
  ),
  comments(
    'comments',
    'Комментарии и ответы',
    'Под вашими публикациями и в ответ на ваши комментарии',
    defaultOn: true,
  ),
  likes(
    'likes',
    'Лайки и реакции',
    'На публикации и на сообщения',
    defaultOn: true,
  ),
  mentions(
    'mentions',
    'Упоминания',
    'Когда вас назвали по @нику',
    defaultOn: true,
  ),
  follows('follows', 'Новые подписчики', 'Кто на вас подписался', defaultOn: false),
  events('events', 'События', 'Запись, изменения и отмена', defaultOn: false),
  quests('quests', 'Квесты', 'Заявки и решения по вашим квестам', defaultOn: false),
  needs('needs', 'Отклики «Мне надо»', 'Кто готов помочь', defaultOn: false),
  points('points', 'Баллы и приглашения', 'Начисления и новые приглашённые', defaultOn: false);

  const NotificationCategory(
    this.key,
    this.title,
    this.subtitle, {
    required this.defaultOn,
  });

  final String key;
  final String title;
  final String subtitle;
  final bool defaultOn;
}

/// Настройки уведомлений человека. Хранится только то, что он менял, —
/// остальное берётся из [NotificationCategory.defaultOn].
class NotificationPrefs {
  const NotificationPrefs({
    this.overrides = const {},
    this.quietFrom,
    this.quietTo,
  });

  final Map<String, bool> overrides;

  /// Тихие часы: минуты от полуночи по местному времени. null — не заданы.
  final int? quietFrom;
  final int? quietTo;

  bool get hasQuietHours => quietFrom != null && quietTo != null;

  bool isOn(NotificationCategory category) =>
      overrides[category.key] ?? category.defaultOn;

  NotificationPrefs withCategory(NotificationCategory category, bool on) {
    final next = {...overrides};
    if (on == category.defaultOn) {
      next.remove(category.key);
    } else {
      next[category.key] = on;
    }
    return NotificationPrefs(overrides: next, quietFrom: quietFrom, quietTo: quietTo);
  }

  NotificationPrefs withQuiet(int? from, int? to) =>
      NotificationPrefs(overrides: overrides, quietFrom: from, quietTo: to);
}

abstract interface class NotificationPrefsRepository {
  Future<NotificationPrefs> load();

  Future<void> save(NotificationPrefs prefs);
}

class SupabaseNotificationPrefsRepository implements NotificationPrefsRepository {
  SupabaseNotificationPrefsRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<NotificationPrefs> load() async {
    final rows = await _client.rpc('my_notification_prefs') as List<dynamic>;
    if (rows.isEmpty) return const NotificationPrefs();
    final row = rows.first as Map<String, dynamic>;
    final raw = row['settings'];
    return NotificationPrefs(
      overrides: {
        if (raw is Map)
          for (final entry in raw.entries)
            if (entry.value is bool) entry.key.toString(): entry.value as bool,
      },
      quietFrom: (row['quiet_from'] as num?)?.toInt(),
      quietTo: (row['quiet_to'] as num?)?.toInt(),
    );
  }

  @override
  Future<void> save(NotificationPrefs prefs) => _client.rpc(
    'set_notification_prefs',
    params: {
      'in_settings': prefs.overrides,
      'in_quiet_from': prefs.quietFrom,
      'in_quiet_to': prefs.quietTo,
      // Сдвиг берётся с телефона при каждом сохранении: переехал в другой
      // часовой пояс — тихие часы поедут вместе с ним после первой правки.
      'in_tz': DateTime.now().timeZoneOffset.inMinutes,
    },
  );
}

class LocalNotificationPrefsRepository implements NotificationPrefsRepository {
  var _prefs = const NotificationPrefs();

  @override
  Future<NotificationPrefs> load() async => _prefs;

  @override
  Future<void> save(NotificationPrefs prefs) async => _prefs = prefs;
}

final notificationPrefsRepositoryProvider = Provider<NotificationPrefsRepository>((ref) {
  ref.keepAlive();
  if (!Env.isConfigured) return LocalNotificationPrefsRepository();
  return SupabaseNotificationPrefsRepository(Supabase.instance.client);
});

class NotificationPrefsController extends AsyncNotifier<NotificationPrefs> {
  @override
  Future<NotificationPrefs> build() async {
    if (ref.watch(currentUserProvider) == null) return const NotificationPrefs();
    return ref.watch(notificationPrefsRepositoryProvider).load();
  }

  /// Тумблер переключается сразу; если сервер не принял — возвращаем как было.
  Future<void> _apply(NotificationPrefs next) async {
    final previous = state.value ?? const NotificationPrefs();
    state = AsyncData(next);
    try {
      await ref.read(notificationPrefsRepositoryProvider).save(next);
    } catch (error) {
      AppLog.add('Настройки уведомлений не сохранились: $error');
      state = AsyncData(previous);
      rethrow;
    }
  }

  Future<void> setCategory(NotificationCategory category, bool on) =>
      _apply((state.value ?? const NotificationPrefs()).withCategory(category, on));

  Future<void> setQuiet(int? from, int? to) =>
      _apply((state.value ?? const NotificationPrefs()).withQuiet(from, to));
}

final notificationPrefsProvider =
    AsyncNotifierProvider<NotificationPrefsController, NotificationPrefs>(
      NotificationPrefsController.new,
    );
