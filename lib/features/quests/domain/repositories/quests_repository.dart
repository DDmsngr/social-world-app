import '../entities/quest.dart';

/// Договор с хранилищем квестов. Цикл ТЗ — создание → заявка → одобрение →
/// чат → QR → участие → завершение (п. 56).
///
/// Действия не возвращают квест: после любого из них экран перечитывает его
/// через [loadQuest] — счётчик мест мог измениться у других людей, и выводить
/// его арифметикой на клиенте нельзя.
///
/// Отказы по правилам (мест нет, код не подошёл) приходят исключением с кодом
/// из `core/errors/rule_violation.dart`.
abstract interface class QuestsRepository {
  /// Квесты вокруг точки — для Pulse. Включает сутки «следа» завершённых
  /// квестов с Moments (п. 42), считая от [at].
  Future<List<Quest>> loadNearby({
    required double latitude,
    required double longitude,
    int radiusMeters = 5000,
    DateTime? at,
  });

  /// Один квест по id — для ссылок, уведомлений, QR и карточки на карте.
  Future<Quest?> loadQuest(String questId);

  /// Возвращает id нового квеста. [photoPath] — файл на устройстве: в
  /// хранилище его кладёт репозиторий. Точка встречи — либо [placeId], либо
  /// пара [latitude]/[longitude] с подписью [placeTitle].
  Future<String> createQuest({
    required String title,
    required DateTime startsAt,
    String? description,
    String? extraInfo,
    String? photoPath,
    DateTime? endsAt,
    String? placeId,
    String? placeTitle,
    double? latitude,
    double? longitude,
    int? maxParticipants,
  });

  /// Подать заявку. Идемпотентно. У квеста без лимита заявка одобряется
  /// сразу — вернётся [QuestParticipationStatus.approved].
  Future<QuestParticipationStatus> requestJoin(String questId);

  /// Отказаться от участия до или во время квеста (п. 23).
  Future<void> withdraw(String questId);

  /// Завершить своё участие. Сам квест продолжает идти (п. 34).
  Future<void> completeParticipation(String questId);

  /// Подтвердить прибытие кодом с QR. После этого GPS не проверяется (п. 33).
  Future<QuestParticipationStatus> confirmArrival({
    required String questId,
    required String code,
  });

  /// Организатор видит всех с заявками, одобренный участник — соучастников,
  /// остальные — пустой список (п. 44).
  Future<List<QuestParticipation>> loadParticipants(String questId);

  /// Решение организатора по заявке (п. 26, 29).
  Future<void> decideRequest({
    required String participationId,
    required bool approved,
  });

  /// Исключить участника — он выходит и из квест-чата (п. 31).
  Future<void> removeParticipant(String participationId);

  /// Мои участия во всех квестах сразу — их может быть несколько активных
  /// одновременно (п. 25). Только свои: чужой список не отдаётся (п. 43, 44).
  Future<List<Quest>> myQuests({bool activeOnly = false});

  /// Квесты, созданные мной.
  Future<List<Quest>> questsIAuthored({bool activeOnly = false});

  Future<void> finishQuest(String questId);
  Future<void> cancelQuest(String questId);

  /// Код прибытия для QR — только организатору.
  Future<String> arrivalCode(String questId);

  /// Новый код, если старый разошёлся по чатам.
  Future<String> rotateArrivalCode(String questId);

  /// Социальная история квеста: Moments по времени (п. 40).
  Future<List<QuestMoment>> loadMoments(String questId);

  /// Принятые правила квестов: `null` — человек их ещё не видел.
  Future<QuestRulesConsent?> loadRulesConsent();
  Future<void> acceptRules(int version);
}
