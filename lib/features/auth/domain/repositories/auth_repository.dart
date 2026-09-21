import '../entities/app_user.dart';

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

  /// Заполнение публичного профиля после первого входа.
  Future<AppUser> completeProfile({required String displayName});

  /// Правка собственной анкеты. `null` — поле не трогаем, пустая строка у
  /// [bio]/[city] — очищаем. [avatarLocalPath] — файл с устройства: в
  /// хранилище его кладёт репозиторий, а ссылка попадает в профиль.
  Future<AppUser> updateProfile({
    String? displayName,
    String? bio,
    String? city,
    String? avatarLocalPath,
  });

  /// Радиус размытия гео на карте «Рядом» — экран настроек.
  Future<AppUser> updateLocationBlur(int meters);
}
