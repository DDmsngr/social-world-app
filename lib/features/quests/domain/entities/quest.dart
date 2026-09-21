/// Квест — реальная городская активность, которую человек находит на Pulse и
/// в которой участвует: прогулка, спорт, игра, визит в заведение.
///
/// Квесты — отдельная сущность, а не переименованные события: события живут
/// своей жизнью и остаются как есть. Модель написана до экранов и до таблиц,
/// чтобы правила ТЗ (несколько одновременных участий, индивидуальное
/// завершение, долгоживущие квесты) были зафиксированы в одном месте.
library;

/// Состояние самого квеста, не участия в нём.
enum QuestStatus {
  /// Идёт: виден на Pulse, принимает заявки, пока есть места.
  active('Идёт'),

  /// Организатор закрыл квест. След на Pulse живёт ещё сутки, если у квеста
  /// есть Moments (ТЗ, п. 42).
  finished('Завершён'),

  cancelled('Отменён');

  const QuestStatus(this.label);

  final String label;

  static QuestStatus parse(String? raw) => QuestStatus.values.firstWhere(
    (status) => status.name == raw,
    orElse: () => QuestStatus.active,
  );
}

/// Где человек находится в жизненном цикле одного квеста.
///
/// Участий у человека может быть несколько одновременно (ТЗ, п. 25): поля
/// «текущий квест» в модели нет и быть не должно.
enum QuestParticipationStatus {
  /// Заявка подана, организатор ещё не ответил (ТЗ, п. 26).
  requested('Заявка отправлена'),

  /// Организатор принял. С этого момента открыт квест-чат (ТЗ, п. 29, 30).
  approved('Вы участвуете'),

  rejected('Заявка отклонена'),

  /// QR отсканирован на месте. Дальше приложение за человеком не следит —
  /// ни маршрута, ни таймера, ни проверок GPS (ТЗ, п. 33).
  arrived('На месте'),

  /// Человек закончил своё участие. Квест при этом продолжает идти для
  /// остальных (ТЗ, п. 34).
  completed('Завершено'),

  /// Отказался сам (ТЗ, п. 23).
  withdrawn('Вы отказались'),

  /// Исключён организатором.
  removed('Исключён');

  const QuestParticipationStatus(this.label);

  final String label;

  /// Участие занимает место из лимита, пока человек не ушёл и не закончил.
  bool get holdsSlot =>
      this == QuestParticipationStatus.approved ||
      this == QuestParticipationStatus.arrived;

  /// Доступ к квест-чату есть у принятых и пришедших; после завершения,
  /// отказа и исключения человек из активного чата выходит (ТЗ, п. 31).
  bool get hasChatAccess => holdsSlot;

  /// Участие активно — показывать в разделе «Активные» профиля.
  bool get isActive =>
      this == QuestParticipationStatus.requested || holdsSlot;

  static QuestParticipationStatus parse(String? raw) =>
      QuestParticipationStatus.values.firstWhere(
        (status) => status.name == raw,
        orElse: () => QuestParticipationStatus.requested,
      );
}

class Quest {
  const Quest({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.title,
    required this.startsAt,
    required this.createdAt,
    this.authorAvatarUrl,
    this.description,
    this.photoUrl,
    this.endsAt,
    this.placeId,
    this.placeTitle,
    this.latitude,
    this.longitude,
    this.maxParticipants,
    this.participantCount = 0,
    this.status = QuestStatus.active,
    this.myStatus,
    this.extraInfo,
  });

  final String id;
  final String authorId;
  final String authorName;
  final String? authorAvatarUrl;

  final String title;
  final String? description;
  final String? photoUrl;

  /// Место встречи. Может быть привязано к заведению: на первом этапе бизнес
  /// заводит обычный аккаунт и создаёт квест от себя (ТЗ, п. 16).
  final String? placeId;
  final String? placeTitle;
  final double? latitude;
  final double? longitude;

  final DateTime startsAt;

  /// Квест не обязан укладываться в сутки: организатор может держать его
  /// открытым днями, и состав участников будет меняться (ТЗ, п. 35, 36).
  final DateTime? endsAt;

  /// Лимит участников. `null` — без лимита (например, «бесплатный кофе»
  /// с одним местом задаётся числом, а прогулка без ограничений — null).
  final int? maxParticipants;
  final int participantCount;

  final QuestStatus status;

  /// Участие того, кто смотрит. `null` — не подавал заявку.
  final QuestParticipationStatus? myStatus;

  /// Необязательное поле формы создания (ТЗ, п. 21).
  final String? extraInfo;

  final DateTime createdAt;

  bool get hasLocation => latitude != null && longitude != null;

  /// Мест больше нет — новые заявки не принимаются (ТЗ, п. 24).
  bool get isFull =>
      maxParticipants != null && participantCount >= maxParticipants!;

  bool get acceptsRequests => status == QuestStatus.active && !isFull;

  /// Сколько мест занято, для подписи «3/10».
  String get occupancy => maxParticipants == null
      ? '$participantCount'
      : '$participantCount/$maxParticipants';
}

/// Заявка или участие конкретного человека. Отдельная сущность, потому что у
/// одного квеста их много, а у одного человека много одновременных участий.
class QuestParticipation {
  const QuestParticipation({
    required this.id,
    required this.questId,
    required this.profileId,
    required this.displayName,
    required this.status,
    required this.requestedAt,
    this.avatarUrl,
    this.socialScore = 0,
    this.arrivedAt,
    this.completedAt,
  });

  final String id;
  final String questId;
  final String profileId;
  final String displayName;
  final String? avatarUrl;

  /// Очки активности заявителя — организатор видит их при разборе заявок
  /// (ТЗ, п. 26). Это не рейтинг качества человека (ТЗ, п. 27, 28).
  final int socialScore;

  final QuestParticipationStatus status;
  final DateTime requestedAt;

  /// Отметка QR на месте.
  final DateTime? arrivedAt;
  final DateTime? completedAt;
}

/// Согласие с правилами квестов. Хранится с версией и временем, чтобы при
/// существенном изменении правил можно было спросить заново (ТЗ, п. 49, 50).
class QuestRulesConsent {
  const QuestRulesConsent({required this.version, required this.acceptedAt});

  /// Версия правил, действующая сейчас. Поднимать при изменении текста.
  static const currentVersion = 1;

  final int version;
  final DateTime acceptedAt;

  bool get isCurrent => version >= currentVersion;
}
