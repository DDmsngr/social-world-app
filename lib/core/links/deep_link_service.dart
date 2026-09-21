import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show RouterDelegate;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/providers/auth_providers.dart';
import '../debug/app_log.dart';
import '../router/app_router.dart';
import 'deep_links.dart';

/// Ловит входящие ссылки и ведёт на объект.
///
/// Ссылка может прийти, когда человека ещё нет в системе (холодный старт,
/// заставка, вход, онбординг): открывать экран в этот момент нельзя — редирект
/// роутера унесёт его на заставку. Поэтому ссылка запоминается и открывается,
/// как только пользователь оказывается внутри приложения.
class DeepLinkService {
  DeepLinkService(this._ref) {
    try {
      _sub = AppLinks().uriLinkStream.listen(
        handleUri,
        onError: (Object error) => AppLog.add('Ссылка не принята: $error'),
      );
    } catch (error) {
      // Нет платформенного плагина (тесты, веб): ссылки просто не ловим.
      AppLog.add('Ссылки недоступны: $error');
    }
    // Роутер сообщает о каждом переходе — в том числе о завершении входа.
    _delegate = _ref.read(routerProvider).routerDelegate;
    _delegate.addListener(tryOpenPending);
  }

  late final RouterDelegate<Object> _delegate;

  final Ref _ref;
  StreamSubscription<Uri>? _sub;
  DeepLink? _pending;

  @visibleForTesting
  DeepLink? get pending => _pending;

  /// `socialworld://auth-callback` сюда не относится — это вход через VK/Яндекс,
  /// им занимается `OAuthDeepLinkListener`.
  void handleUri(Uri uri) {
    final link = DeepLinks.parse(uri);
    if (link == null) return;
    _pending = link;
    tryOpenPending();
  }

  void tryOpenPending() {
    final link = _pending;
    if (link == null) return;

    final user = _ref.read(currentUserProvider);
    if (user == null || !user.hasProfile) return;

    final router = _ref.read(routerProvider);
    final current = router.routerDelegate.currentConfiguration.uri.path;
    if (Routes.authFlow.contains(current)) return;

    _pending = null;
    router.push(link.location);
  }

  void dispose() {
    _sub?.cancel();
    _delegate.removeListener(tryOpenPending);
  }
}

final deepLinkServiceProvider = Provider<DeepLinkService>((ref) {
  ref.keepAlive();
  final service = DeepLinkService(ref);
  ref.onDispose(service.dispose);
  // Вход мог завершиться уже после прихода ссылки.
  ref.listen(currentUserProvider, (_, _) => service.tryOpenPending());
  return service;
});
