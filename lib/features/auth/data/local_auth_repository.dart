import 'dart:async';
import 'dart:math';

import '../domain/entities/app_user.dart';
import '../domain/repositories/auth_repository.dart';

/// Заглушка на время, пока self-hosted Supabase не поднят.
///
/// Письмо никуда не уходит — код генерируется здесь и показывается в интерфейсе
/// через [issuedCode]. Поведение остальной части экрана при этом такое же, как
/// с настоящим бэкендом: код надо ввести, неверный не пройдёт.
class LocalAuthRepository implements AuthRepository {
  final _controller = StreamController<AppUser?>.broadcast();
  final _random = Random();

  AppUser? _user;
  String? _pendingEmail;
  String? _issuedCode;

  /// Последний выданный код — только для режима разработки.
  String? get issuedCode => _issuedCode;

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
    _issuedCode = (100000 + _random.nextInt(900000)).toString();
  }

  @override
  Future<AppUser> verifyEmailCode({
    required String email,
    required String code,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (code.trim() != _issuedCode) {
      throw Exception('Неверный код');
    }
    return _openSession(
      AppUser(id: 'local-user', email: _pendingEmail ?? email.trim()),
    );
  }

  /// Вход мимо почты и кода — кнопка в dev-панели.
  /// [displayName] пустой означает «показать онбординг».
  Future<AppUser> devSignIn({String? displayName}) async {
    return _openSession(
      AppUser(
        id: 'dev-user',
        email: 'dev@socialworld.ru',
        displayName: displayName,
        socialScore: displayName == null ? 0 : 128,
      ),
    );
  }

  @override
  Future<void> signOut() async {
    _user = null;
    _issuedCode = null;
    _pendingEmail = null;
    _controller.add(null);
  }

  @override
  Future<AppUser> completeProfile({required String displayName}) async {
    final current = _user;
    if (current == null) throw Exception('Нет активной сессии');
    return _openSession(current.copyWith(displayName: displayName.trim()));
  }

  @override
  Future<AppUser> updateProfile({
    String? displayName,
    String? bio,
    String? city,
    String? avatarLocalPath,
  }) async {
    final current = _user;
    if (current == null) throw Exception('Нет активной сессии');
    await Future<void>.delayed(const Duration(milliseconds: 200));
    return _openSession(
      AppUser(
        id: current.id,
        email: current.email,
        phone: current.phone,
        displayName: displayName?.trim() ?? current.displayName,
        // В моках хранилища нет: ссылкой на аватар служит сам путь к файлу.
        avatarUrl: avatarLocalPath ?? current.avatarUrl,
        bio: bio == null ? current.bio : (bio.trim().isEmpty ? null : bio.trim()),
        city: city == null
            ? current.city
            : (city.trim().isEmpty ? null : city.trim()),
        socialScore: current.socialScore,
        locationBlurM: current.locationBlurM,
      ),
    );
  }

  @override
  Future<AppUser> updateLocationBlur(int meters) async {
    final current = _user;
    if (current == null) throw Exception('Нет активной сессии');
    return _openSession(current.copyWith(locationBlurM: meters));
  }

  AppUser _openSession(AppUser user) {
    _user = user;
    _controller.add(user);
    return user;
  }
}
