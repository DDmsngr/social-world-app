class AppUser {
  const AppUser({
    required this.id,
    this.email,
    this.phone,
    this.displayName,
    this.avatarUrl,
    this.avatarVideoUrl,
    this.bio,
    this.city,
    this.socialScore = 0,
    this.locationBlurM = 500,
    this.username,
    this.onboarded = true,
    this.birthDate,
    this.ageRequired = false,
  });

  final String id;
  final String? email;
  final String? phone;
  final String? displayName;
  final String? avatarUrl;

  /// Видеоаватар (премиум). Пока флаг `Features.videoAvatar` выключен, нигде
  /// не показывается.
  final String? avatarVideoUrl;
  final String? bio;
  final String? city;
  final int socialScore;

  /// Радиус, с которым человек виден на карте «Рядом» — точные координаты
  /// снапятся к ячейке сетки этого размера. Совпадает с дефолтом и check-
  /// ограничением (>= 200) колонки profiles.location_blur_m из 0001_init.sql.
  final int locationBlurM;

  /// @ник без «@»: латиница, цифры и _, 3–20 знаков. null — ещё не выбран.
  final String? username;

  /// Знакомство пройдено (имя и город). Вход через VK/Яндекс сразу заполняет
  /// имя, поэтому одного имени для этого мало.
  final bool onboarded;

  /// Дата рождения: видна только самому человеку (таблица profile_ages).
  final DateTime? birthDate;

  /// Возраст обязателен: настоящий сервер просит его у всех. В тестах и
  /// локальном режиме не требуется (как и [onboarded], по умолчанию «да»).
  final bool ageRequired;

  /// Нужно спросить дату рождения: гоним на экран возраста.
  bool get needsAge => ageRequired && birthDate == null;

  /// Полных лет на [now]; null — дата неизвестна.
  int? ageOn(DateTime now) {
    final born = birthDate;
    if (born == null) return null;
    var years = now.year - born.year;
    if (now.month < born.month || (now.month == born.month && now.day < born.day)) years--;
    return years;
  }

  /// Совершеннолетний ли. Дата не указана: при обязательном возрасте — нет
  /// (стикеры 18+ скрыты, пока человек её не назовёт), без него — да.
  bool get isAdult {
    final years = ageOn(DateTime.now());
    return years == null ? !ageRequired : years >= 18;
  }

  /// Пока профиль не заполнен — гоним пользователя в онбординг.
  bool get hasProfile => (displayName ?? '').trim().isNotEmpty && onboarded;

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
    String? avatarVideoUrl,
    bool clearAvatarVideo = false,
    String? bio,
    String? city,
    int? socialScore,
    int? locationBlurM,
    String? username,
    DateTime? birthDate,
  }) =>
      AppUser(
        id: id,
        email: email,
        phone: phone,
        displayName: displayName ?? this.displayName,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        avatarVideoUrl: clearAvatarVideo ? null : (avatarVideoUrl ?? this.avatarVideoUrl),
        bio: bio ?? this.bio,
        city: city ?? this.city,
        socialScore: socialScore ?? this.socialScore,
        locationBlurM: locationBlurM ?? this.locationBlurM,
        username: username ?? this.username,
        onboarded: onboarded,
        birthDate: birthDate ?? this.birthDate,
        ageRequired: ageRequired,
      );
}
