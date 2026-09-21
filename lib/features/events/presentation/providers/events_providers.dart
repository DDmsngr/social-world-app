import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/env.dart';
import '../../../../core/debug/app_log.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../moderation/presentation/providers/report_providers.dart';
import '../../../profile/presentation/providers/profile_providers.dart';
import '../../data/local_events_repository.dart';
import '../../data/supabase_events_repository.dart';
import '../../domain/entities/event.dart';
import '../../domain/repositories/events_repository.dart';

final eventsRepositoryProvider = Provider<EventsRepository>((ref) {
  // keepAlive: у заглушки события лежат в памяти, пересоздание стёрло бы
  // всё, что пользователь успел создать.
  ref.keepAlive();
  if (!Env.isConfigured) {
    return LocalEventsRepository(
      currentUserId: () => ref.read(currentUserProvider)?.id ?? 'local-user',
      currentUserName: () =>
          ref.read(currentUserProvider)?.displayName ?? 'Вы',
    );
  }
  return SupabaseEventsRepository(Supabase.instance.client);
});

class EventsController extends AsyncNotifier<List<Event>> {
  @override
  Future<List<Event>> build() async {
    ref.keepAlive();
    // См. FeedController.build() — та же защита от запроса без сессии сразу
    // после выхода, когда resetSessionScopedProviders пересоздаёт провайдер.
    if (ref.watch(currentUserProvider) == null) return const [];
    final events = await ref.watch(eventsRepositoryProvider).loadEvents();
    return _withoutHidden(events);
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final events = await ref.read(eventsRepositoryProvider).loadEvents();
      return _withoutHidden(events);
    });
  }

  final _joinsInFlight = <String>{};

  /// Возвращает false, если записаться не удалось — экран показывает
  /// сообщение. Молчаливый отказ здесь хуже, чем в ленте: человек уверен,
  /// что придёт на встречу, а в списке участников его нет.
  Future<bool> toggleJoin(Event stale) async {
    if (!_joinsInFlight.add(stale.id)) return true;
    // Экран мог передать устаревший снимок (например, тот, с которым его
    // открыли): решает всегда то, что сейчас лежит в списке.
    final event = byId(stale.id) ?? stale;

    _replace(
      event.copyWith(
        joinedByMe: !event.joinedByMe,
        participantCount: event.participantCount + (event.joinedByMe ? -1 : 1),
      ),
    );

    try {
      _replace(await ref.read(eventsRepositoryProvider).toggleJoin(event));
      return true;
    } catch (error) {
      AppLog.add('Участие не сохранилось: $error');
      _replace(event);
      return false;
    } finally {
      _joinsInFlight.remove(event.id);
    }
  }

  void _replace(Event updated) {
    state = AsyncValue.data([
      for (final item in state.value ?? const <Event>[])
        if (item.id == updated.id) updated else item,
    ]);
  }

  Event? byId(String id) {
    for (final item in state.value ?? const <Event>[]) {
      if (item.id == id) return item;
    }
    return null;
  }

  /// Событие по id: из списка, а если его там нет (ссылка, уведомление,
  /// перезапуск) — с сервера, с добавлением в список.
  Future<Event?> ensure(String id) async {
    final known = byId(id);
    if (known != null) return known;
    final fetched = await ref.read(eventsRepositoryProvider).loadEvent(id);
    if (fetched != null) append(fetched);
    return fetched;
  }

  void append(Event event) {
    state = AsyncValue.data([...?state.value, event]);
  }

  void remove(String id) {
    state = AsyncValue.data([
      for (final item in state.value ?? const <Event>[])
        if (item.id != id) item,
    ]);
  }

  /// После жалобы контент исчезает сразу, не дожидаясь разбора.
  void hide(String targetId) {
    state = AsyncValue.data([
      for (final item in state.value ?? const <Event>[])
        if (item.id != targetId && item.authorId != targetId) item,
    ]);
  }

  List<Event> _withoutHidden(List<Event> events) {
    final hidden = {
      ...ref.read(reportRepositoryProvider).hiddenTargetIds,
      ...?ref.read(blocksProvider).value?.keys,
    };
    if (hidden.isEmpty) return events;
    return events
        .where(
          (event) =>
              !hidden.contains(event.id) && !hidden.contains(event.authorId),
        )
        .toList(growable: false);
  }
}

final eventsProvider = AsyncNotifierProvider<EventsController, List<Event>>(
  EventsController.new,
);

/// Кто идёт на событие. После «Участвовать» экран инвалидирует этот провайдер,
/// чтобы человек сразу увидел себя в списке.
final eventParticipantsProvider = FutureProvider.autoDispose
    .family<List<EventParticipant>, String>((ref, eventId) {
      return ref.watch(eventsRepositoryProvider).loadParticipants(eventId);
    });
