class AppUser {
  const AppUser({
    required this.id,
    this.email,
    this.phone,
    this.displayName,
    this.avatarUrl,
    this.socialScore = 0,
  });

  final String id;
  final String? email;
  final String? phone;
  final String? displayName;
  final String? avatarUrl;
  final int socialScore;

  /// Пока профиль не заполнен — гоним пользователя в онбординг.
  bool get hasProfile => (displayName ?? '').trim().isNotEmpty;

  AppUser copyWith({
    String? displayName,
    String? avatarUrl,
    int? socialScore,
  }) =>
      AppUser(
        id: id,
        email: email,
        phone: phone,
        displayName: displayName ?? this.displayName,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        socialScore: socialScore ?? this.socialScore,
      );
}
