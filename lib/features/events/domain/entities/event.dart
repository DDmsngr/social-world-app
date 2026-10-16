import 'event_route.dart';

/// Как попасть на событие (events.join_mode, миграция 0104).
enum EventJoinMode {
  /// Записаться сразу.
  free('free', 'Свободный вход', 'Любой записывается сам'),

  /// Человек рассказывает о себе, организатор принимает или отклоняет.
  request('request', 'По запросу', 'Организатор принимает по рассказу о себе'),

  /// Видно только тем, кого организатор позвал.
  invite('invite', 'По приглашению', 'Видят только приглашённые');

  const EventJoinMode(this.wire, this.label, this.hint);

  final String wire;
  final String label;
  final String hint;

  static EventJoinMode parse(Object? raw) =>
      values.firstWhere((m) => m.wire == raw, orElse: () => free);
}

class Event {
  const Event({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.title,
    required this.startsAt,
    required this.createdAt,
    this.authorAvatarUrl,
    this.description,
    this.endsAt,
    this.placeId,
    this.placeTitle,
    this.latitude,
    this.longitude,
    this.coverUrl,
    this.routePoints = const [],
    this.participantCount = 0,
    this.joinedByMe = false,
    this.participantsPreview = const [],
    this.joinMode = EventJoinMode.free,
    this.maxParticipants,
    this.myRequestStatus,
    this.pendingRequests = 0,
  });

  final String id;
  final String authorId;
  final String authorName;
  final String? authorAvatarUrl;
  final String title;
  final String? description;
  final DateTime startsAt;
  final DateTime? endsAt;

  final String? placeId;

  /// Название места, а не координаты — тот же принцип, что и у постов.
  final String? placeTitle;

  /// Точка места, к которому привязано событие. Нет места — нет и метки на
  /// карте, событие остаётся только в списке.
  final double? latitude;
  final double? longitude;

  final String? coverUrl;

  /// Маршрут события: последовательность точек. Пустой — маршрута нет.
  final List<EventRoutePoint> routePoints;

  final DateTime createdAt;
  final int participantCount;
  final bool joinedByMe;

  /// До четырёх участников для мини-аватарок на карточке: сначала друзья.
  final List<EventParticipant> participantsPreview;

  final EventJoinMode joinMode;

  /// Лимит участников; null — без ограничений.
  final int? maxParticipants;

  /// Мой запрос на участие: pending / approved / rejected / withdrawn; null — не просил.
  final String? myRequestStatus;

  /// Сколько запросов ждёт решения — видит только организатор.
  final int pendingRequests;

  bool get isFull => maxParticipants != null && participantCount >= maxParticipants!;

  bool get isPast => (endsAt ?? startsAt).isBefore(DateTime.now());

  bool get hasLocation => latitude != null && longitude != null;
  bool get hasRoute => routePoints.length >= 2;

  Event copyWith({
    int? participantCount,
    bool? joinedByMe,
    double? latitude,
    double? longitude,
    String? myRequestStatus,
    bool clearMyRequest = false,
    int? pendingRequests,
  }) => Event(
    id: id,
    authorId: authorId,
    authorName: authorName,
    authorAvatarUrl: authorAvatarUrl,
    title: title,
    description: description,
    startsAt: startsAt,
    endsAt: endsAt,
    placeId: placeId,
    placeTitle: placeTitle,
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
    coverUrl: coverUrl,
    routePoints: routePoints,
    createdAt: createdAt,
    participantCount: participantCount ?? this.participantCount,
    joinedByMe: joinedByMe ?? this.joinedByMe,
    participantsPreview: participantsPreview,
    joinMode: joinMode,
    maxParticipants: maxParticipants,
    myRequestStatus: clearMyRequest ? null : (myRequestStatus ?? this.myRequestStatus),
    pendingRequests: pendingRequests ?? this.pendingRequests,
  );
}

/// Участник события — строка списка «Кто идёт».
class EventParticipant {
  const EventParticipant({
    required this.profileId,
    required this.displayName,
    this.avatarUrl,
    this.isFriend = false,
  });

  final String profileId;
  final String displayName;
  final String? avatarUrl;

  /// Есть связь по подписке (в любую сторону). Такие идут в списке первыми.
  final bool isFriend;
}

/// Запрос на участие во встрече «по запросу» — строка списка организатора.
class JoinRequest {
  const JoinRequest({
    required this.id,
    required this.profileId,
    required this.displayName,
    required this.about,
    required this.status,
    required this.createdAt,
    this.avatarUrl,
    this.message,
  });

  final String id;
  final String profileId;
  final String displayName;
  final String? avatarUrl;

  /// Рассказ человека о себе.
  final String about;

  /// Зачем он хочет прийти (необязательно).
  final String? message;

  /// pending / approved / rejected.
  final String status;
  final DateTime createdAt;

  bool get isPending => status == 'pending';
}

/// Друг, которого можно позвать на встречу.
class InviteCandidate {
  const InviteCandidate({
    required this.profileId,
    required this.displayName,
    this.username,
    this.avatarUrl,
  });

  final String profileId;
  final String displayName;
  final String? username;
  final String? avatarUrl;
}
