import '../entities/app_user.dart';

/// Ник уже занят другим человеком.
class UsernameTakenException implements Exception {
  const UsernameTakenException();

  @override
  String toString() => 'Этот ник уже занят';
}

/// Правила @ника: латиница в нижнем регистре, цифры и _, 3–20 знаков.
/// Совпадает с check profiles_username_format в миграции 0062.
abstract final class Username {
  static final _format = RegExp(r'^[a-z0-9_]{3,20}$');

  /// Приводит ввод к виду, в котором ник хранится: без «@» и пробелов,
  /// в нижнем регистре.
  static String normalize(String raw) => raw.trim().replaceFirst('@', '').toLowerCase();

  /// Текст ошибки для поля ввода или null, если ник годится (пустой тоже
  /// годится: ник необязателен).
  static String? validate(String raw) {
    final nick = normalize(raw);
    if (nick.isEmpty) return null;
    if (nick.length < 3) return 'Минимум 3 знака';
    if (nick.length > 20) return 'Максимум 20 знаков';
    if (!_format.hasMatch(nick)) return 'Только латиница, цифры и _';
    return null;
  }
}

abstract interface class AuthRepository {
  Stream<AppUser?> authStateChanges();

  AppUser? get currentUser;

  /// Отправляет одноразовый код на email.
  Future<void> requestEmailCode(String email);

  /// Проверяет код и открывает сессию.
  Future<AppUser> verifyEmailCode({
    required String email,
    required String code,
  });

  Future<void> signOut();

  /// Безвозвратно удаляет аккаунт и все данные профиля, затем выходит.
  Future<void> deleteAccount();

  /// Знакомство после первого входа: имя, город и, по желанию, @ник.
  /// Отмечает онбординг пройденным.
  Future<AppUser> completeProfile({
    required String displayName,
    required String city,
    String? username,
  });

  /// Правка собственной анкеты. `null` — поле не трогаем, пустая строка у
  /// [bio]/[city]/[username] — очищаем. [avatarLocalPath] — файл с
  /// устройства: в хранилище его кладёт репозиторий, а ссылка попадает в
  /// профиль. Занятый ник — [UsernameTakenException].
  Future<AppUser> updateProfile({
    String? displayName,
    String? bio,
    String? city,
    String? username,
    String? avatarLocalPath,
  });

  /// Радиус размытия гео на карте «Рядом» — экран настроек.
  Future<AppUser> updateLocationBlur(int meters);
}
