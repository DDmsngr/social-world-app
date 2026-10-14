import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/debug/app_log.dart';
import '../../core/errors/friendly_error.dart';
import '../../core/router/app_router.dart';
import 'invites.dart';
import 'presentation/invite_code_dialog.dart';

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
      if (pending == null) {
        await _askOnce(repo, overview.code);
        return;
      }
      await PendingInvite.clear();
      if (pending.code == overview.code) return;

      if (pending.source != 'clipboard') unawaited(repo.track('referral_app_opened', {'code': pending.code}));
      await _claim(repo, pending.code, pending.source, quietOnError: pending.source == 'clipboard');
    } catch (error) {
      AppLog.add('Приглашения: $error');
    } finally {
      _running = false;
    }
  }

  Future<void> _claim(InviteRepository repo, String code, String source, {bool quietOnError = false}) async {
    try {
      final inviter = await repo.claim(code, source: source);
      _toast(inviter == null ? 'Приглашение принято' : 'Вас пригласил(а) $inviter. Добро пожаловать!');
      _ref.invalidate(referralOverviewProvider);
    } catch (error) {
      AppLog.add('Приглашение не принято: $error');
      // Из буфера обмена код мог попасть случайно — молчим.
      if (!quietOnError) _toast(friendlyError(error, fallback: 'Код приглашения не принят'));
    }
  }

  /// Ни ссылки, ни буфера: человек мог получить файл приложения и просто
  /// поставить его. Новичка один раз спрашиваем, не позвал ли его кто-то, —
  /// иначе пригласивший не получит очки. Тем, кто зарегистрировался давно, не
  /// спрашиваем (сервер всё равно не примет код позже недели).
  Future<void> _askOnce(InviteRepository repo, String ownCode) async {
    if (await PendingInvite.wasPrompted()) return;
    if (!await repo.claimOpen()) return;
    final navigator = _ref.read(routerProvider).routerDelegate.navigatorKey;
    if (navigator.currentContext == null) return;
    await PendingInvite.markPrompted();
    final context = navigator.currentContext;
    if (context == null || !context.mounted) return;
    final code = await askInviteCode(
      context,
      title: 'Вас пригласили в ChaWo?',
      message: 'Если вас позвал друг, введите его код. Он есть у него в «Профиль → Пригласить», '
          'и вы оба получите очки.',
      cancelLabel: 'Пропустить',
    );
    if (code == null || code == ownCode) return;
    await _claim(repo, code, 'manual');
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
