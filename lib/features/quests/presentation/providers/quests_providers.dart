import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/env.dart';
import '../../../../core/debug/app_log.dart';
import '../../../../core/errors/friendly_error.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../discover/presentation/providers/discover_providers.dart';
import '../../../moderation/presentation/providers/report_providers.dart';
import '../../../profile/presentation/providers/profile_providers.dart';
import '../../data/local_quests_repository.dart';
import '../../data/supabase_quests_repository.dart';
import '../../domain/entities/quest.dart';
import '../../domain/repositories/quests_repository.dart';

final questsRepositoryProvider = Provider<QuestsRepository>((ref) {
  // keepAlive: у заглушки квесты лежат в памяти, пересоздание стёрло бы всё,
  // что человек успел создать и пройти.
  ref.keepAlive();
  if (!Env.isConfigured) {
    return LocalQuestsRepository(
      currentUserId: () => ref.read(currentUserProvider)?.id ?? 'local-user',
      currentUserName: () => ref.read(currentUserProvider)?.displayName ?? 'Вы',
    );
  }
  return SupabaseQuestsRepository(Supabase.instance.client);
});

/// Квесты для Pulse — вокруг той же точки, что и остальная карта (город или
/// якорь «Рядом»). Сбой не роняет карту: просто без квестов.
final pulseQuestsProvider = FutureProvider<List<Quest>>((ref) async {
  ref.keepAlive();
  if (ref.watch(currentUserProvider) == null) return const [];
  final anchor = ref.watch(nearbyAnchorProvider);
  final center = anchor != null
      ? (latitude: anchor.latitude, longitude: anchor.longitude)
      : await ref.watch(discoverCenterProvider.future);
  try {
    final quests = await ref
        .watch(questsRepositoryProvider)
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
      for (final quest in quests)
        if (!hidden.contains(quest.id) && !hidden.contains(quest.authorId)) quest,
    ];
  } catch (error) {
    AppLog.add('Квесты для карты не загрузились: $error');
    return const [];
  }
});

/// Один квест — всегда свежий с сервера: счётчик мест и мой статус меняются
/// от действий других людей.
final questProvider = FutureProvider.autoDispose.family<Quest?, String>(
  (ref, questId) => ref.watch(questsRepositoryProvider).loadQuest(questId),
);

final questParticipantsProvider = FutureProvider.autoDispose
    .family<List<QuestParticipation>, String>(
      (ref, questId) => ref.watch(questsRepositoryProvider).loadParticipants(questId),
    );

final questMomentsProvider = FutureProvider.autoDispose
    .family<List<QuestMoment>, String>(
      (ref, questId) => ref.watch(questsRepositoryProvider).loadMoments(questId),
    );

/// Разделы «🎯 Квесты» в профиле (п. 43).
enum MyQuestsTab {
  active('Активные'),
  history('История'),
  authored('Созданные мной');

  const MyQuestsTab(this.label);

  final String label;
}

final myQuestsProvider = FutureProvider.autoDispose
    .family<List<Quest>, MyQuestsTab>((ref, tab) async {
      final repo = ref.watch(questsRepositoryProvider);
      switch (tab) {
        case MyQuestsTab.active:
          return repo.myQuests(activeOnly: true);
        case MyQuestsTab.history:
          final all = await repo.myQuests();
          return [
            for (final quest in all)
              if (!(quest.isActive && (quest.myStatus?.isActive ?? false))) quest,
          ];
        case MyQuestsTab.authored:
          return repo.questsIAuthored();
      }
    });

final questRulesConsentProvider = FutureProvider.autoDispose<QuestRulesConsent?>(
  (ref) => ref.watch(questsRepositoryProvider).loadRulesConsent(),
);

/// Действия с квестом. Каждое возвращает `null` при успехе или текст ошибки
/// для snackbar и после любого исхода перечитывает всё, что от него зависит:
/// карточку, участников, «мои квесты» и метки на Pulse.
class QuestActions {
  QuestActions(this._ref);

  final Ref _ref;

  QuestsRepository get _repo => _ref.read(questsRepositoryProvider);

  void _refresh(String questId) {
    _ref
      ..invalidate(questProvider(questId))
      ..invalidate(questParticipantsProvider(questId))
      ..invalidate(myQuestsProvider)
      ..invalidate(pulseQuestsProvider);
  }

  Future<String?> _run(
    String questId,
    String what,
    Future<void> Function() action,
  ) async {
    try {
      await action();
      return null;
    } catch (error) {
      AppLog.add('Квест: $what не удалось: $error');
      return friendlyError(error, fallback: 'Не удалось: $what');
    } finally {
      _refresh(questId);
    }
  }

  Future<String?> requestJoin(String questId) =>
      _run(questId, 'подать заявку', () => _repo.requestJoin(questId));

  Future<String?> withdraw(String questId) =>
      _run(questId, 'отказаться', () => _repo.withdraw(questId));

  Future<String?> complete(String questId) =>
      _run(questId, 'завершить участие', () => _repo.completeParticipation(questId));

  Future<String?> confirmArrival(String questId, String code) => _run(
    questId,
    'отметить прибытие',
    () => _repo.confirmArrival(questId: questId, code: code),
  );

  Future<String?> decide(String questId, String participationId, {required bool approve}) =>
      _run(
        questId,
        approve ? 'принять заявку' : 'отклонить заявку',
        () => _repo.decideRequest(participationId: participationId, approved: approve),
      );

  Future<String?> remove(String questId, String participationId) => _run(
    questId,
    'исключить участника',
    () => _repo.removeParticipant(participationId),
  );

  Future<String?> finish(String questId) =>
      _run(questId, 'завершить квест', () => _repo.finishQuest(questId));

  Future<String?> cancel(String questId) =>
      _run(questId, 'отменить квест', () => _repo.cancelQuest(questId));
}

final questActionsProvider = Provider<QuestActions>((ref) {
  ref.keepAlive();
  return QuestActions(ref);
});
