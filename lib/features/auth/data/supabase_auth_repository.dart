import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/entities/app_user.dart';
import '../domain/repositories/auth_repository.dart';

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client) {
    // completeProfile меняет только таблицу profiles — GoTrue об этом не
    // знает и onAuthStateChange не сработает, поэтому роутер (он слушает
    // именно этот стрим) никогда не узнал бы, что анкета заполнена, и
    // держал бы пользователя на онбординге навечно. Прокидываем обновление
    // вручную через свой контроллер.
    _authSub = _auth.onAuthStateChange.listen((state) async {
      final user = state.session?.user;
      _controller.add(user == null ? null : await _withProfile(user));
    });
  }

  final SupabaseClient _client;
  final _controller = StreamController<AppUser?>.broadcast();
  late final StreamSubscription<AuthState> _authSub;

  GoTrueClient get _auth => _client.auth;

  @override
  Stream<AppUser?> authStateChanges() async* {
    yield currentUser;
    yield* _controller.stream;
  }

  @override
  AppUser? get currentUser {
    final user = _auth.currentUser;
    return user == null ? null : _fromAuthUser(user);
  }

  @override
  Future<void> requestEmailCode(String email) =>
      _auth.signInWithOtp(email: email.trim());

  @override
  Future<AppUser> verifyEmailCode({
    required String email,
    required String code,
  }) async {
    final response = await _auth.verifyOTP(
      email: email.trim(),
      token: code.trim(),
      type: OtpType.email,
    );
    final user = response.user;
    if (user == null) {
      throw const AuthException('Не удалось открыть сессию');
    }
    return _withProfile(user);
  }

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<AppUser> completeProfile({required String displayName}) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const AuthException('Нет активной сессии');
    }
    // Без таймаута зависший запрос (плохая сеть/VPN) выглядит как немая
    // кнопка навечно — экрана ошибки никто не увидит.
    final row = await _client
        .from('profiles')
        .upsert({'id': user.id, 'display_name': displayName.trim()})
        .select()
        .single()
        .timeout(const Duration(seconds: 15));
    final merged = _merge(user, row);
    _controller.add(merged);
    return merged;
  }

  @override
  Future<AppUser> updateLocationBlur(int meters) async {
    final user = _auth.currentUser;
    if (user == null) throw const AuthException('Нет активной сессии');

    final row = await _client
        .from('profiles')
        .update({'location_blur_m': meters})
        .eq('id', user.id)
        .select()
        .single();
    final merged = _merge(user, row);
    _controller.add(merged);
    return merged;
  }

  void dispose() {
    _authSub.cancel();
    _controller.close();
  }

  Future<AppUser> _withProfile(User user) async {
    final row = await _client
        .from('profiles')
        .select()
        .eq('id', user.id)
        .maybeSingle();
    return row == null ? _fromAuthUser(user) : _merge(user, row);
  }

  AppUser _fromAuthUser(User user) => AppUser(
        id: user.id,
        email: user.email,
        phone: user.phone,
      );

  AppUser _merge(User user, Map<String, dynamic> row) => AppUser(
        id: user.id,
        email: user.email,
        phone: user.phone,
        displayName: row['display_name'] as String?,
        avatarUrl: row['avatar_url'] as String?,
        socialScore: (row['social_score'] as num?)?.toInt() ?? 0,
        locationBlurM: (row['location_blur_m'] as num?)?.toInt() ?? 500,
      );
}
