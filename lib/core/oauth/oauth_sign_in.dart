import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:app_links/app_links.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/env.dart';
import '../debug/app_log.dart';

enum OAuthBridgeProvider { vk, yandex }

/// Секрет одного входа. Приложение придумывает его перед тем, как открыть
/// браузер, серверу отдаёт только хеш (`app_challenge`), а сам предъявляет
/// при обмене кода на сессию. Так ссылка `socialworld://auth-callback`,
/// перехваченная или подсунутая чужим приложением, ничего не даёт: код без
/// секрета бесполезен, а чужой код нашему секрету не подходит.
abstract final class OAuthSecret {
  static String generate([Random? random]) {
    final rng = random ?? Random.secure();
    final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// base64url (без «=») от SHA-256 секрета — ровно то, что проверяет сервер.
  static String challengeOf(String secret) =>
      base64Url.encode(sha256.convert(utf8.encode(secret)).bytes).replaceAll('=', '');
}

/// Где лежит секрет, пока человек ходит в браузер. Android может выгрузить
/// приложение за это время, поэтому не в памяти.
abstract interface class PendingOAuthStore {
  Future<void> save(String secret, DateTime at);

  /// Возвращает секрет, если вход начат не раньше [ttl] назад, и стирает его
  /// при любом исходе: одна попытка на один вход.
  Future<String?> take(DateTime now, Duration ttl);
}

class SecurePendingOAuthStore implements PendingOAuthStore {
  const SecurePendingOAuthStore();

  static const _key = 'oauth_pending_login';
  static const _storage = FlutterSecureStorage();

  @override
  Future<void> save(String secret, DateTime at) =>
      _storage.write(key: _key, value: '$secret|${at.millisecondsSinceEpoch}');

  @override
  Future<String?> take(DateTime now, Duration ttl) async {
    final raw = await _storage.read(key: _key);
    await _storage.delete(key: _key);
    if (raw == null) return null;
    final parts = raw.split('|');
    if (parts.length != 2) return null;
    final at = int.tryParse(parts[1]);
    if (at == null) return null;
    final age = now.millisecondsSinceEpoch - at;
    return (age >= 0 && age <= ttl.inMilliseconds) ? parts[0] : null;
  }
}

/// Сколько времени у человека на вход у провайдера. Совпадает с сервером.
const oauthPendingTtl = Duration(minutes: 10);

/// Открывает системный браузер на мосту входа (см. Edge Functions
/// `oauth-{vk,yandex}-start` на бэкенде) — сам обмен кодами и выдача сессии
/// целиком на сервере, приложению остаётся поймать редирект обратно.
Future<void> startOAuthSignIn(
  OAuthBridgeProvider provider, {
  PendingOAuthStore store = const SecurePendingOAuthStore(),
}) async {
  final path = switch (provider) {
    OAuthBridgeProvider.vk => 'oauth-vk-start',
    OAuthBridgeProvider.yandex => 'oauth-yandex-start',
  };
  final secret = OAuthSecret.generate();
  await store.save(secret, DateTime.now());
  final uri = Uri.parse('${Env.supabaseUrl}/functions/v1/$path').replace(
    queryParameters: {'app_challenge': OAuthSecret.challengeOf(secret)},
  );
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Слушает редирект `socialworld://auth-callback?code=...`, меняет код на
/// сессию (функция oauth-exchange) и применяет её к клиенту Supabase. Живёт
/// всю жизнь приложения — подписывается один раз при первом обращении (см.
/// `oauthDeepLinkProvider`).
///
/// Ссылка без начатого входа игнорируется. Токены из самой ссылки не берутся
/// никогда: так делали старые версии, и чужая ссылка с токеном злоумышленника
/// переключала человека в чужой аккаунт.
class OAuthDeepLinkListener {
  OAuthDeepLinkListener({
    this._store = const SecurePendingOAuthStore(),
    http.Client? client,
    Stream<Uri>? links,
    Future<void> Function(String refreshToken)? applySession,
    DateTime Function()? now,
  }) : _client = client ?? http.Client(),
       _applySession = applySession ?? _defaultApplySession,
       _now = now ?? DateTime.now {
    final stream = links ?? _tryAppLinks();
    _sub = stream?.listen(handle, onError: (_) {});
  }

  final PendingOAuthStore _store;
  final http.Client _client;
  final Future<void> Function(String refreshToken) _applySession;
  final DateTime Function() _now;
  StreamSubscription<Uri>? _sub;

  static Stream<Uri>? _tryAppLinks() {
    try {
      return AppLinks().uriLinkStream;
    } catch (error) {
      // Нет платформенного плагина (тесты, веб): ссылки просто не ловим.
      AppLog.add('Ссылки входа недоступны: $error');
      return null;
    }
  }

  static Future<void> _defaultApplySession(String refreshToken) async {
    await Supabase.instance.client.auth.setSession(refreshToken);
  }

  @visibleForTesting
  Future<void> handle(Uri uri) async {
    if (uri.scheme != 'socialworld' || uri.host != 'auth-callback') return;
    if (!Env.isConfigured) return;

    final code = uri.queryParameters['code'];
    if (code == null || code.isEmpty) return;

    // Вход не начинали (или секрет протух) — это чужая ссылка.
    final secret = await _store.take(_now(), oauthPendingTtl);
    if (secret == null) return;

    try {
      final response = await _client
          .post(
            Uri.parse('${Env.supabaseUrl}/functions/v1/oauth-exchange'),
            headers: {
              'Content-Type': 'application/json',
              'apikey': Env.supabaseAnonKey,
            },
            body: jsonEncode({'code': code, 'secret': secret}),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        AppLog.add('Обмен кода входа: ${response.statusCode}');
        return;
      }
      final refreshToken =
          (jsonDecode(response.body) as Map<String, dynamic>)['refresh_token'] as String?;
      if (refreshToken == null || refreshToken.isEmpty) return;
      await _applySession(refreshToken);
    } catch (error) {
      AppLog.add('Обмен кода входа не удался: $error');
    }
  }

  void dispose() {
    _sub?.cancel();
    _client.close();
  }
}

final oauthDeepLinkProvider = Provider<OAuthDeepLinkListener>((ref) {
  // Riverpod 3 диспозит провайдеры без слушателей по умолчанию — а этот
  // должен пережить весь экран входа, поэтому держим его руками.
  ref.keepAlive();
  final listener = OAuthDeepLinkListener();
  ref.onDispose(listener.dispose);
  return listener;
});
