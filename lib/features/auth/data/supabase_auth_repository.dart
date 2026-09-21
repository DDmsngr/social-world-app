import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/debug/app_log.dart';
import '../../../core/media/media_uploader.dart';
import '../domain/entities/app_user.dart';
import '../domain/repositories/auth_repository.dart';

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client) {
    // GoTrue's onAuthStateChange — ReplaySubject: новому подписчику сразу
    // приходит initialSession/текущая сессия, поэтому отдельный синхронный
    // yield currentUser в authStateChanges() не нужен — раньше именно он
    // создавал гонку: голый Auth-юзер без имени успевал дойти до роутера
    // раньше настоящего профиля, и уже онбордингнутый человек на миг видел
    // экран онбординга. Теперь один канал на все события: initialSession и
    // последующие идут через один и тот же обработчик с защитой от гонки.
    _authSub = _auth.onAuthStateChange.listen(
      _handleAuthEvent,
      onError: (Object error, StackTrace stack) {
        AppLog.add('Auth-стрим упал: $error');
      },
    );
  }

  final SupabaseClient _client;
  final _controller = StreamController<AppUser?>.broadcast();
  late final StreamSubscription<AuthState> _authSub;

  GoTrueClient get _auth => _client.auth;

  /// Растёт на каждое auth-событие и на каждую собственную запись профиля
  /// (completeProfile/updateLocationBlur). Устаревший ответ — тот, чьё
  /// поколение не совпадает с текущим на момент завершения — просто не
  /// публикуется. Закрывает две гонки разом: позднее событие логаута после
  /// начала загрузки профиля и старый fetch профиля, завершившийся после
  /// того, как человек уже сохранил новое имя.
  var _generation = 0;
  AppUser? _lastKnown;

  Future<void> _handleAuthEvent(AuthState state) async {
    final myGeneration = ++_generation;
    final user = state.session?.user;

    if (user == null) {
      _lastKnown = null;
      _controller.add(null);
      return;
    }

    final resolved = await _withProfile(user, fallbackTo: _lastKnown);
    if (myGeneration != _generation) return; // событие устарело
    _lastKnown = resolved;
    _controller.add(resolved);
  }

  @override
  Stream<AppUser?> authStateChanges() => _controller.stream;

  @override
  AppUser? get currentUser {
    final user = _auth.currentUser;
    if (user == null) return null;
    // Между событиями стрима отдаём последний известный профиль того же
    // пользователя, а не голый Auth-объект без имени — иначе любой код,
    // читающий currentUser синхронно между событиями, увидел бы «профиль не
    // заполнен» для уже онбордингнутого человека.
    return _lastKnown?.id == user.id ? _lastKnown : _fromAuthUser(user);
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
    // verifyOTP уже вызывает onAuthStateChange → _handleAuthEvent сам
    // опубликует объединённый профиль; здесь просто отдаём его вызывающему
    // коду тем же путём, без второго независимого запроса.
    return _withProfile(user, fallbackTo: _lastKnown);
  }

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<AppUser> completeProfile({required String displayName}) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const AuthException('Нет активной сессии');
    }

    final myGeneration = ++_generation;
    // update, а не upsert: строку профиля уже создал handle_new_user при
    // регистрации (0001_init.sql), а после 0011 клиенту не выдано право
    // писать в id — INSERT ... ON CONFLICT DO UPDATE от upsert такое право
    // потребовал бы даже не трогая id по существу.
    final row = await _client
        .from('profiles')
        .update({'display_name': displayName.trim()})
        .eq('id', user.id)
        .select()
        .single()
        .timeout(const Duration(seconds: 15));

    final merged = _merge(user, row);
    if (myGeneration == _generation) {
      _lastKnown = merged;
      _controller.add(merged);
    }
    return merged;
  }

  @override
  Future<AppUser> updateProfile({
    String? displayName,
    String? bio,
    String? city,
    String? avatarLocalPath,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw const AuthException('Нет активной сессии');

    final changes = <String, dynamic>{};
    if (displayName != null) changes['display_name'] = displayName.trim();
    if (bio != null) changes['bio'] = bio.trim().isEmpty ? null : bio.trim();
    if (city != null) changes['city'] = city.trim().isEmpty ? null : city.trim();
    if (avatarLocalPath != null) {
      // Файл уезжает в бакет `avatars` до записи в профиль: сорвавшаяся
      // загрузка не оставит в анкете ссылку на несуществующую картинку.
      changes['avatar_url'] = await MediaUploader(
        _client,
        bucket: 'avatars',
      ).upload(avatarLocalPath);
    }
    if (changes.isEmpty) return _lastKnown ?? _fromAuthUser(user);

    final myGeneration = ++_generation;
    // Читаем обратно то, что реально записала база (после триггеров и
    // проверок), а не собираем профиль из того, что отправили.
    final row = await _client
        .from('profiles')
        .update(changes)
        .eq('id', user.id)
        .select()
        .single()
        .timeout(const Duration(seconds: 20));

    final merged = _merge(user, row);
    if (myGeneration == _generation) {
      _lastKnown = merged;
      _controller.add(merged);
    }
    return merged;
  }

  @override
  Future<AppUser> updateLocationBlur(int meters) async {
    final user = _auth.currentUser;
    if (user == null) throw const AuthException('Нет активной сессии');

    final myGeneration = ++_generation;
    final row = await _client
        .from('profiles')
        .update({'location_blur_m': meters})
        .eq('id', user.id)
        .select()
        .single();

    final merged = _merge(user, row);
    if (myGeneration == _generation) {
      _lastKnown = merged;
      _controller.add(merged);
    }
    return merged;
  }

  void dispose() {
    _authSub.cancel();
    _controller.close();
  }

  Future<AppUser> _withProfile(User user, {AppUser? fallbackTo}) async {
    Future<Map<String, dynamic>?> fetch() => _client
        .from('profiles')
        .select()
        .eq('id', user.id)
        .maybeSingle()
        .timeout(const Duration(seconds: 15));

    try {
      final row = await fetch();
      return row == null ? _fromAuthUser(user) : _merge(user, row);
    } catch (error) {
      // Один повтор почти всегда достаточно для разового сбоя сети/VPN на
      // холодном старте — не хочется откатывать человека на онбординг из-за
      // одной моргнувшей попытки.
      try {
        await Future<void>.delayed(const Duration(seconds: 2));
        final row = await fetch();
        return row == null ? _fromAuthUser(user) : _merge(user, row);
      } catch (retryError) {
        AppLog.add('Загрузка профиля не удалась: $retryError');
        // Этот UID уже был опознан раньше — отдаём прошлый снимок, а не
        // «профиль не заполнен»: иначе уже онбордингнутого человека унесёт
        // на онбординг из-за разового сбоя сети.
        if (fallbackTo != null && fallbackTo.id == user.id) return fallbackTo;
        return _fromAuthUser(user);
      }
    }
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
        bio: row['bio'] as String?,
        city: row['city'] as String?,
        socialScore: (row['social_score'] as num?)?.toInt() ?? 0,
        locationBlurM: (row['location_blur_m'] as num?)?.toInt() ?? 500,
      );
}
