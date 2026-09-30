import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/debug/app_log.dart';
import '../../../auth/presentation/providers/auth_providers.dart';

/// Сообщения, скрытые «только у меня». Живут на устройстве и привязаны к
/// аккаунту: собеседник их по-прежнему видит, а серверу незачем знать, что
/// человек у себя почистил.
class HiddenMessages extends Notifier<Set<String>> {
  /// Больше не храним: старые скрытые всё равно уехали за пределы истории.
  static const _limit = 2000;

  String? _uid;

  String get _key => 'chat.hidden.$_uid';

  @override
  Set<String> build() {
    ref.keepAlive();
    _uid = ref.watch(currentUserProvider.select((user) => user?.id));
    if (_uid != null) unawaited(_load());
    return const {};
  }

  Future<void> _load() async {
    final uid = _uid;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!ref.mounted || uid != _uid) return;
      state = {...?prefs.getStringList(_key), ...state};
    } catch (error) {
      AppLog.add('Скрытые сообщения не прочитались: $error');
    }
  }

  void hide(Iterable<String> ids) {
    state = {...state, ...ids};
    unawaited(_save());
  }

  void unhide(Iterable<String> ids) {
    state = {...state}..removeAll(ids);
    unawaited(_save());
  }

  Future<void> _save() async {
    if (_uid == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = state.toList();
      await prefs.setStringList(
        _key,
        list.length > _limit ? list.sublist(list.length - _limit) : list,
      );
    } catch (error) {
      AppLog.add('Скрытые сообщения не сохранились: $error');
    }
  }
}

final hiddenMessagesProvider = NotifierProvider<HiddenMessages, Set<String>>(
  HiddenMessages.new,
);
