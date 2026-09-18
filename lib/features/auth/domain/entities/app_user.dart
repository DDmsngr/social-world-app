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

  /// Мост входа через VK ID/Яндекс ID заводит служебный адрес вида
  /// `vk.<external_id>@id.socialworld.internal`, чтобы у auth.users была
  /// строка email — это не контакт человека, а обёртка над его VK/Яндекс id.
  /// Показывать его в профиле нельзя: это раскрывает исходный аккаунт.
  static const _syntheticEmailSuffix = '@id.socialworld.internal';
  bool get hasSyntheticEmail => email?.endsWith(_syntheticEmailSuffix) ?? false;

  /// То, что можно показать человеку рядом с именем — реальная почта или
  /// телефон, а не служебный адрес моста OAuth.
  String? get displayContact => hasSyntheticEmail ? null : (email ?? phone);

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
