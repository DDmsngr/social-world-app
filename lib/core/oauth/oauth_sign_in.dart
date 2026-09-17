import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/env.dart';

enum OAuthBridgeProvider { vk, yandex }

/// Открывает системный браузер на мосту входа (см. Edge Functions
/// `oauth-{vk,yandex}-start` на бэкенде) — сам обмен кодами и выдача сессии
/// целиком на сервере, приложению остаётся поймать редирект обратно.
Future<void> startOAuthSignIn(OAuthBridgeProvider provider) async {
  final path = switch (provider) {
    OAuthBridgeProvider.vk => 'oauth-vk-start',
    OAuthBridgeProvider.yandex => 'oauth-yandex-start',
  };
  final uri = Uri.parse('${Env.supabaseUrl}/functions/v1/$path');
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Слушает редирект `socialworld://auth-callback#access_token=...` и
/// применяет сессию к клиенту Supabase. Живёт всю жизнь приложения —
/// подписывается один раз при первом обращении (см. `oauthDeepLinkProvider`).
class OAuthDeepLinkListener {
  OAuthDeepLinkListener() {
    _appLinks = AppLinks();
    _sub = _appLinks.uriLinkStream.listen(_handle, onError: (_) {});
  }

  late final AppLinks _appLinks;
  late final StreamSubscription<Uri> _sub;

  void _handle(Uri uri) {
    if (uri.scheme != 'socialworld' || uri.host != 'auth-callback') return;
    if (!Env.isConfigured) return;

    // Токены летят во фрагменте (#...), а не в query — Uri их туда же и
    // кладёт при парсинге кастомных схем, разбираем руками как query-строку.
    final raw = uri.fragment.isNotEmpty ? uri.fragment : uri.query;
    final params = Uri.splitQueryString(raw);

    final refreshToken = params['refresh_token'];
    if (refreshToken == null) return;

    Supabase.instance.client.auth.setSession(refreshToken);
  }

  void dispose() {
    _sub.cancel();
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
