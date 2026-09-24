import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/env.dart';
import '../../../../core/debug/app_log.dart';
import '../../../../core/errors/friendly_error.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../discover/presentation/providers/discover_providers.dart';
import '../../../moderation/presentation/providers/report_providers.dart';
import '../../../profile/presentation/providers/profile_providers.dart';
import '../../data/local_needs_repository.dart';
import '../../data/supabase_needs_repository.dart';
import '../../domain/entities/need_request.dart';
import '../../domain/repositories/needs_repository.dart';

final needsRepositoryProvider = Provider<NeedsRepository>((ref) {
  ref.keepAlive();
  if (!Env.isConfigured) {
    return LocalNeedsRepository(
      currentUserId: () => ref.read(currentUserProvider)?.id ?? 'local-user',
      currentUserName: () => ref.read(currentUserProvider)?.displayName ?? 'Вы',
    );
  }
  return SupabaseNeedsRepository(Supabase.instance.client);
});

/// Просьбы для Pulse — вокруг той же точки, что и вся карта. Сбой не роняет
/// карту: просто без просьб.
final pulseNeedsProvider = FutureProvider<List<NeedRequest>>((ref) async {
  ref.keepAlive();
  if (ref.watch(currentUserProvider) == null) return const [];
  final anchor = ref.watch(nearbyAnchorProvider);
  final center = anchor != null
      ? (latitude: anchor.latitude, longitude: anchor.longitude)
      : await ref.watch(discoverCenterProvider.future);
  try {
    final needs = await ref
        .watch(needsRepositoryProvider)
        .loadNearby(
          latitude: center.latitude,
          longitude: center.longitude,
          radiusMeters: anchor == null ? 5000 : (anchor.radiusMeters * 1.2).round(),
        );
    final hidden = {
      ...ref.read(reportRepositoryProvider).hiddenTargetIds,
      ...?ref.read(blocksProvider).value?.keys,
    };
    return [
      for (final need in needs)
        if (!hidden.contains(need.id) && !hidden.contains(need.authorId)) need,
    ];
  } catch (error) {
    AppLog.add('Просьбы для карты не загрузились: $error');
    return const [];
  }
});

final needProvider = FutureProvider.autoDispose.family<NeedRequest?, String>(
  (ref, needId) => ref.watch(needsRepositoryProvider).loadNeed(needId),
);

final needResponsesProvider = FutureProvider.autoDispose
    .family<List<NeedResponse>, String>(
      (ref, needId) => ref.watch(needsRepositoryProvider).loadResponses(needId),
    );

final myNeedsProvider = FutureProvider.autoDispose<List<NeedRequest>>(
  (ref) => ref.watch(needsRepositoryProvider).myNeeds(),
);

/// Действия с просьбой: `null` — успех, иначе текст для snackbar.
class NeedActions {
  NeedActions(this._ref);

  final Ref _ref;

  NeedsRepository get _repo => _ref.read(needsRepositoryProvider);

  void _refresh(String needId) {
    _ref
      ..invalidate(needProvider(needId))
      ..invalidate(needResponsesProvider(needId))
      ..invalidate(myNeedsProvider)
      ..invalidate(pulseNeedsProvider);
  }

  Future<String?> _run(String needId, String what, Future<void> Function() action) async {
    try {
      await action();
      return null;
    } catch (error) {
      AppLog.add('«Мне надо»: $what не удалось: $error');
      return friendlyError(error, fallback: 'Не удалось: $what');
    } finally {
      _refresh(needId);
    }
  }

  Future<String?> respond(String needId, {String? text}) =>
      _run(needId, 'откликнуться', () => _repo.respond(needId, text: text));

  Future<String?> withdrawResponse(String needId) =>
      _run(needId, 'отозвать отклик', () => _repo.withdrawResponse(needId));

  Future<String?> close(String needId) =>
      _run(needId, 'закрыть просьбу', () => _repo.closeNeed(needId));

  Future<String?> delete(String needId) =>
      _run(needId, 'удалить просьбу', () => _repo.deleteNeed(needId));
}

final needActionsProvider = Provider<NeedActions>((ref) {
  ref.keepAlive();
  return NeedActions(ref);
});
