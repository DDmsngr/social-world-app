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
}
