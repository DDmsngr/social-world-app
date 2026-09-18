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
    this.placeTitle,
    this.latitude,
    this.longitude,
    this.coverUrl,
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

  /// Название места, а не координаты — тот же принцип, что и у постов.
  final String? placeTitle;

  /// Точка места, к которому привязано событие. Нет места — нет и метки на
  /// карте, событие остаётся только в списке.
  final double? latitude;
  final double? longitude;

  final String? coverUrl;

  final DateTime createdAt;
  final int participantCount;
  final bool joinedByMe;

  bool get isPast => (endsAt ?? startsAt).isBefore(DateTime.now());

  bool get hasLocation => latitude != null && longitude != null;

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
    placeTitle: placeTitle,
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
    coverUrl: coverUrl,
    createdAt: createdAt,
    participantCount: participantCount ?? this.participantCount,
    joinedByMe: joinedByMe ?? this.joinedByMe,
  );
}
