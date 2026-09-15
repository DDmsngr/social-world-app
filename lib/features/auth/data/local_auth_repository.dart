import 'dart:async';

import '../domain/entities/app_user.dart';
import '../domain/repositories/auth_repository.dart';

/// Заглушка на время, пока self-hosted Supabase не поднят.
/// Позволяет собирать и гонять UI целиком, не дожидаясь сервера.
/// Код подтверждения — любой из шести цифр.
class LocalAuthRepository implements AuthRepository {
  final _controller = StreamController<AppUser?>.broadcast();
  AppUser? _user;
  String? _pendingEmail;

  @override
  Stream<AppUser?> authStateChanges() async* {
    yield _user;
    yield* _controller.stream;
  }

  @override
  AppUser? get currentUser => _user;

  @override
  Future<void> requestEmailCode(String email) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    _pendingEmail = email.trim();
  }

  @override
  Future<AppUser> verifyEmailCode({
    required String email,
    required String code,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (code.trim().length != 6) {
      throw Exception('Код из шести цифр');
    }
    _user = AppUser(id: 'local-user', email: _pendingEmail ?? email.trim());
    _controller.add(_user);
    return _user!;
  }

  @override
  Future<void> signOut() async {
    _user = null;
    _controller.add(null);
  }

  @override
  Future<AppUser> completeProfile({required String displayName}) async {
    final current = _user;
    if (current == null) throw Exception('Нет активной сессии');
    _user = current.copyWith(displayName: displayName.trim());
    _controller.add(_user);
    return _user!;
  }
}
