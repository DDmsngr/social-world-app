import 'event_route.dart';

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

  bool get isPast => (endsAt ?? startsAt).isBefore(DateTime.now());

  bool get hasLocation => latitude != null && longitude != null;
  bool get hasRoute => routePoints.length >= 2;

  Event copyWith({
    int? participantCount,
    bool? joinedByMe,
    double? latitude,
    double? longitude,
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
  );
}

/// Участник события — строка списка «Кто идёт».
class EventParticipant {
  const EventParticipant({
    required this.profileId,
    required this.displayName,
    this.avatarUrl,
  });

  final String profileId;
  final String displayName;
  final String? avatarUrl;
}
