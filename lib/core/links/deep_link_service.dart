import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show RouterDelegate;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/providers/auth_providers.dart';
import '../../features/referrals/presentation/providers/referrals_providers.dart';
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
      // Холодный старт: приложение запущено ярлыком или ссылкой, пока было
      // закрыто. Ссылку запуска поток не обязан отдавать — спрашиваем явно.
      // Спрашиваем один раз за запуск процесса: при возврате из фона та же
      // ссылка пришла бы второй раз.
      if (!_launchChecked) {
        _launchChecked = true;
        unawaited(
          AppLinks().getInitialLink().then((uri) {
            if (uri != null) handleUri(uri);
          }).catchError((Object error) {
            AppLog.add('Ссылка запуска не прочиталась: $error');
          }),
        );
      }
    } catch (error) {
      // Нет платформенного плагина (тесты, веб): ссылки просто не ловим.
      AppLog.add('Ссылки недоступны: $error');
    }
    // Роутер сообщает о каждом переходе — в том числе о завершении входа.
    _delegate = _ref.read(routerProvider).routerDelegate;
    _delegate.addListener(tryOpenPending);
  }

  late final RouterDelegate<Object> _delegate;

  static var _launchChecked = false;

  /// Одна и та же ссылка, пришедшая и из потока, и из запроса запуска, не
  /// должна открыть экран дважды.
  String? _lastUri;
  DateTime _lastAt = DateTime(0);

  final Ref _ref;
  StreamSubscription<Uri>? _sub;
  DeepLink? _pending;

  /// Код места с реферального QR (см. миграцию 0025). В отличие от [_pending]
  /// не ведёт ни на какой экран — только отмечается на сервере, человек
  /// остаётся там, где был.
  String? _pendingReferral;

  @visibleForTesting
  DeepLink? get pending => _pending;

  @visibleForTesting
  String? get pendingReferral => _pendingReferral;

  /// `socialworld://auth-callback` сюда не относится — это вход через VK/Яндекс,
  /// им занимается `OAuthDeepLinkListener`.
  void handleUri(Uri uri) {
    final now = DateTime.now();
    if (_lastUri == uri.toString() && now.difference(_lastAt) < const Duration(seconds: 4)) {
      return;
    }
    _lastUri = uri.toString();
    _lastAt = now;

    final referral = DeepLinks.parseReferralCode(uri);
    if (referral != null) _pendingReferral = referral;

    final link = DeepLinks.parse(uri);
    if (link != null) _pending = link;

    if (referral != null || link != null) tryOpenPending();
  }

  void tryOpenPending() {
    final user = _ref.read(currentUserProvider);
    if (user == null || !user.hasProfile) return;

    // Запись кода — не отменяет и не задерживает открытие обычной ссылки:
    // это два независимых действия одного визита.
    final referral = _pendingReferral;
    if (referral != null) {
      _pendingReferral = null;
      unawaited(_recordReferral(referral));
    }

    final link = _pending;
    if (link == null) return;

    final router = _ref.read(routerProvider);
    final current = router.routerDelegate.currentConfiguration.uri.path;
    if (Routes.authFlow.contains(current)) return;

    _pending = null;
    router.push(link.location);
  }

  /// Сбой — не повод мешать человеку: он просто не попал в статистику этого
  /// места. Повторно код можно ввести вручную в настройках.
  Future<void> _recordReferral(String code) async {
    try {
      await _ref.read(referralsRepositoryProvider).recordSignup(code);
    } catch (error) {
      AppLog.add('Код места не засчитался: $error');
    }
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
