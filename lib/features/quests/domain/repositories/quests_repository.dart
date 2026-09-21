import '../entities/quest.dart';

/// Договор с хранилищем квестов. Написан до реализаций, чтобы у экранов и у
/// таблиц была общая форма: цикл ТЗ — создание → заявка → одобрение → чат →
/// QR → участие → завершение (п. 56).
abstract interface class QuestsRepository {
  /// Квесты вокруг точки — для Pulse. [at] задаёт момент времени, чтобы
  /// «сутки следа» у завершённых квестов считались от него, а не от now().
  Future<List<Quest>> loadNearby({
    required double latitude,
    required double longitude,
    int radiusMeters = 5000,
    DateTime? at,
  });

  /// Один квест по id — для ссылок, уведомлений и карточки на карте.
  Future<Quest?> loadQuest(String questId);

  Future<Quest> createQuest({
    required String title,
    required DateTime startsAt,
    String? description,
    String? photoUrl,
    DateTime? endsAt,
    String? placeId,
    String? placeTitle,
    int? maxParticipants,
    String? extraInfo,
  });

  /// Подать заявку. Идемпотентно: повторный вызов не создаёт вторую заявку.
  Future<Quest> requestJoin(String questId);

  /// Отказаться от участия до или во время квеста (ТЗ, п. 23).
  Future<Quest> withdraw(String questId);

  /// Завершить своё участие. Сам квест продолжает идти (ТЗ, п. 34).
  Future<Quest> completeParticipation(String questId);

  /// Подтвердить прибытие по QR. После этого GPS не проверяется (ТЗ, п. 33).
  Future<Quest> confirmArrival({required String questId, required String code});

  /// Заявки и участники — организатору для разбора, остальным для списка.
  Future<List<QuestParticipation>> loadParticipants(String questId);

  /// Решение организатора по заявке (ТЗ, п. 26, 29).
  Future<void> decideRequest({
    required String participationId,
    required bool approved,
  });

  /// Мои участия во всех квестах сразу: их может быть несколько активных
  /// одновременно (ТЗ, п. 25). Чужому человеку этот список не показывается
  /// (ТЗ, п. 43, 44).
  Future<List<Quest>> myQuests({bool activeOnly = false});

  /// Квесты, созданные мной.
  Future<List<Quest>> questsIAuthored();

  Future<void> finishQuest(String questId);
  Future<void> cancelQuest(String questId);

  /// Принятые правила квестов: `null` — человек их ещё не видел.
  Future<QuestRulesConsent?> loadRulesConsent();
  Future<void> acceptRules(int version);
}
