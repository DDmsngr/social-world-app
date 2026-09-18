import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/env.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../moderation/presentation/providers/report_providers.dart';
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

  Future<void> toggleJoin(Event event) async {
    final updated = await ref.read(eventsRepositoryProvider).toggleJoin(event);
    state = AsyncValue.data([
      for (final item in state.value ?? const <Event>[])
        if (item.id == updated.id) updated else item,
    ]);
  }

  void append(Event event) {
    state = AsyncValue.data([...?state.value, event]);
  }

  /// После жалобы контент исчезает сразу, не дожидаясь разбора.
  void hide(String targetId) {
    state = AsyncValue.data([
      for (final item in state.value ?? const <Event>[])
        if (item.id != targetId && item.authorId != targetId) item,
    ]);
  }

  List<Event> _withoutHidden(List<Event> events) {
    final hidden = ref.read(reportRepositoryProvider).hiddenTargetIds;
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
