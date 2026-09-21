class AppUser {
  const AppUser({
    required this.id,
    this.email,
    this.phone,
    this.displayName,
    this.avatarUrl,
    this.bio,
    this.city,
    this.socialScore = 0,
    this.locationBlurM = 500,
  });

  final String id;
  final String? email;
  final String? phone;
  final String? displayName;
  final String? avatarUrl;
  final String? bio;
  final String? city;
  final int socialScore;

  /// Радиус, с которым человек виден на карте «Рядом» — точные координаты
  /// снапятся к ячейке сетки этого размера. Совпадает с дефолтом и check-
  /// ограничением (>= 200) колонки profiles.location_blur_m из 0001_init.sql.
  final int locationBlurM;

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
    String? bio,
    String? city,
    int? socialScore,
    int? locationBlurM,
  }) =>
      AppUser(
        id: id,
        email: email,
        phone: phone,
        displayName: displayName ?? this.displayName,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        bio: bio ?? this.bio,
        city: city ?? this.city,
        socialScore: socialScore ?? this.socialScore,
        locationBlurM: locationBlurM ?? this.locationBlurM,
      );
}
