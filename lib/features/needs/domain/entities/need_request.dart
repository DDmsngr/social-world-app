/// «Мне надо» — просьба, привязанная к городу: «нужно установить телевизор»,
/// «ищу машину из Сочи в Краснодар», «ищу напарника для тенниса» (ТЗ, п. 15).
///
/// От поста отличается тем, что у неё есть адресат и срок: она висит на Pulse,
/// пока актуальна, и закрывается, когда вопрос решён.
library;

enum NeedStatus {
  open('Ищу'),
  closed('Вопрос решён');

  const NeedStatus(this.label);

  final String label;

  static NeedStatus parse(String? raw) => NeedStatus.values.firstWhere(
    (status) => status.name == raw,
    orElse: () => NeedStatus.open,
  );
}

class NeedRequest {
  const NeedRequest({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.text,
    required this.createdAt,
    this.authorAvatarUrl,
    this.placeId,
    this.placeTitle,
    this.latitude,
    this.longitude,
    this.expiresAt,
    this.status = NeedStatus.open,
    this.replyCount = 0,
    this.respondedByMe = false,
  });

  final String id;
  final String authorId;
  final String authorName;
  final String? authorAvatarUrl;

  final String text;

  /// Точка на карте. Как и у постов, наружу отдаётся место, а не координаты
  /// человека: «Мне надо» не должно выдавать чей-то адрес.
  final String? placeId;
  final String? placeTitle;
  final double? latitude;
  final double? longitude;

  final DateTime createdAt;

  /// Просьба перестаёт висеть на карте сама. `null` — срок не задан.
  final DateTime? expiresAt;

  final NeedStatus status;

  /// Сколько человек откликнулись «могу помочь».
  final int replyCount;
  final bool respondedByMe;

  bool get hasLocation => latitude != null && longitude != null;

  bool get isExpired =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now());

  /// Показывать на Pulse стоит только живые просьбы.
  bool get isVisible => status == NeedStatus.open && !isExpired;

  NeedRequest copyWith({
    NeedStatus? status,
    int? replyCount,
    bool? respondedByMe,
    double? latitude,
    double? longitude,
  }) => NeedRequest(
    id: id,
    authorId: authorId,
    authorName: authorName,
    authorAvatarUrl: authorAvatarUrl,
    text: text,
    placeId: placeId,
    placeTitle: placeTitle,
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
    createdAt: createdAt,
    expiresAt: expiresAt,
    status: status ?? this.status,
    replyCount: replyCount ?? this.replyCount,
    respondedByMe: respondedByMe ?? this.respondedByMe,
  );
}

/// Отклик на просьбу. Виден всем, кто видит просьбу, — как комментарий.
class NeedResponse {
  const NeedResponse({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.createdAt,
    this.authorAvatarUrl,
    this.text,
  });

  final String id;
  final String authorId;
  final String authorName;
  final String? authorAvatarUrl;
  final String? text;
  final DateTime createdAt;
}
