import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/debug/app_log.dart';
import '../../core/errors/friendly_error.dart';
import '../../core/router/app_router.dart';
import 'invites.dart';

/// Связывает нового человека с пригласившим, когда он уже вошёл: код из
/// ссылки (запомнен до входа) или из буфера обмена (страница приглашения
/// положила его туда перед скачиванием). Плюс отметка устройства для
/// антифрода — на каждом запуске.
class InviteClaimer {
  InviteClaimer(this._ref);

  final Ref _ref;
  bool _running = false;

  Future<void> run() async {
    final repo = _ref.read(inviteRepositoryProvider);
    if (repo == null || _running) return;
    _running = true;
    try {
      unawaited(repo.reportDevice().catchError((Object e) => AppLog.add('Устройство не отметилось: $e')));
      final overview = await repo.load();
      if (!overview.canClaim) {
        await PendingInvite.clear();
        return;
      }
      var pending = await PendingInvite.load();
      if (pending == null) {
        final fromClipboard = await PendingInvite.takeFromClipboardOnce();
        if (fromClipboard != null) pending = (code: fromClipboard, source: 'clipboard');
      }
      if (pending == null) return;
      await PendingInvite.clear();
      if (pending.code == overview.code) return;

      if (pending.source != 'clipboard') unawaited(repo.track('referral_app_opened', {'code': pending.code}));
      try {
        final inviter = await repo.claim(pending.code, source: pending.source);
        _toast(inviter == null ? 'Приглашение принято' : 'Вас пригласил(а) $inviter. Добро пожаловать!');
        _ref.invalidate(referralOverviewProvider);
      } catch (error) {
        AppLog.add('Приглашение не принято: $error');
        // Из буфера обмена код мог попасть случайно — молчим.
        if (pending.source != 'clipboard') {
          _toast(friendlyError(error, fallback: 'Код приглашения не принят'));
        }
      }
    } catch (error) {
      AppLog.add('Приглашения: $error');
    } finally {
      _running = false;
    }
  }

  void _toast(String text) {
    final context = _ref.read(routerProvider).routerDelegate.navigatorKey.currentContext;
    if (context == null) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text)));
  }
}

final inviteClaimerProvider = Provider<InviteClaimer>((ref) {
  ref.keepAlive();
  return InviteClaimer(ref);
});
