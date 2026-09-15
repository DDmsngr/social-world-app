import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/entities/app_user.dart';
import '../domain/repositories/auth_repository.dart';

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client);

  final SupabaseClient _client;

  GoTrueClient get _auth => _client.auth;

  @override
  Stream<AppUser?> authStateChanges() async* {
    yield currentUser;
    await for (final state in _auth.onAuthStateChange) {
      final user = state.session?.user;
      yield user == null ? null : await _withProfile(user);
    }
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
    final row = await _client
        .from('profiles')
        .upsert({'id': user.id, 'display_name': displayName.trim()})
        .select()
        .single();
    return _merge(user, row);
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
      );
}
