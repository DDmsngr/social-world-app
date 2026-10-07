import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/env.dart';
import '../../core/debug/app_log.dart';

/// Персональные приглашения (миграция 0059). Ссылка ведёт на страницу на
/// нашем домене: там кнопка «Скачать» и код, который страница кладёт в буфер
/// обмена, — после установки приложение само его оттуда подхватит.
abstract final class InviteLinks {
  static const host = 'api-socialworld.deepdrift.tech';
  static const _path = 'r';
  static final _code = RegExp(r'^[A-Za-z2-9]{6,10}$');

  /// `https://api-socialworld.deepdrift.tech/r/ABC234`.
  static Uri shareUri(String code) => Uri.https(host, '/$_path/$code');

  /// Разбирает `socialworld://r/<код>` и `https://<наш домен>/r/<код>`.
  static String? parse(Uri uri) {
    final String? code;
    if (uri.scheme == 'socialworld' && uri.host == _path) {
      code = uri.pathSegments.firstOrNull;
    } else if ((uri.scheme == 'https' || uri.scheme == 'http') && uri.host == host) {
      final parts = uri.pathSegments.where((p) => p.isNotEmpty).toList();
      code = parts.length == 2 && parts.first == _path ? parts.last : null;
    } else {
      return null;
    }
    return code != null && _code.hasMatch(code) ? code.toUpperCase() : null;
  }

  /// Текст, который страница приглашения кладёт в буфер обмена:
  /// «Код приглашения в ChaWo: ABC234».
  static String? fromClipboard(String? text) {
    if (text == null) return null;
    final match = RegExp(r'код приглашения в chawo:\s*([a-z2-9]{6,10})', caseSensitive: false).firstMatch(text);
    return match?.group(1)?.toUpperCase();
  }
}

/// Строка в истории начислений.
class PointTx {
  const PointTx({
    required this.id,
    required this.amount,
    required this.code,
    required this.status,
    required this.at,
    this.level,
    this.reason,
    this.who,
  });

  final String id;
  final int amount;
  final String code;

  /// pending / confirmed / cancelled / reversed.
  final String status;
  final DateTime at;
  final int? level;
  final String? reason;

  /// Имя — только у своих прямых приглашённых.
  final String? who;

  factory PointTx.fromJson(Map<String, dynamic> j) => PointTx(
    id: j['id'] as String,
    amount: (j['amount'] as num).toInt(),
    code: j['code'] as String,
    status: j['status'] as String,
    at: DateTime.parse(j['at'] as String).toLocal(),
    level: (j['level'] as num?)?.toInt(),
    reason: j['reason'] as String?,
    who: j['who'] as String?,
  );

  String get statusLabel => switch (status) {
    'pending' => 'ожидает подтверждения',
    'confirmed' => 'подтверждено',
    'cancelled' => 'отменено',
    'reversed' => 'списано',
    _ => status,
  };

  String get title {
    if (code.startsWith('referral_level_')) {
      final who = this.who;
      return level == 1 && who != null ? 'Приглашение: $who' : 'Приглашение, уровень $level';
    }
    return reason ?? 'Списание';
  }
}

/// Человек, которого я пригласил напрямую.
class InviteEntry {
  const InviteEntry({required this.id, required this.name, required this.at, required this.status, required this.points, this.avatar});

  final String id;
  final String name;
  final String? avatar;
  final DateTime at;
  final String status;
  final int points;

  factory InviteEntry.fromJson(Map<String, dynamic> j) => InviteEntry(
    id: j['id'] as String,
    name: (j['name'] as String?)?.trim().isNotEmpty == true ? j['name'] as String : 'Новый участник',
    avatar: j['avatar'] as String?,
    at: DateTime.parse(j['at'] as String).toLocal(),
    status: j['status'] as String,
    points: (j['points'] as num?)?.toInt() ?? 0,
  );

  String get statusLabel => switch (status) {
    'waiting' => 'ожидает активации',
    'activated' => 'активирован',
    'expired' => 'не активировался',
    'suspicious' => 'проверяется',
    'rejected' => 'отменён',
    _ => status,
  };
}

class ReferralOverview {
  const ReferralOverview({
    required this.enabled,
    required this.code,
    required this.levelPoints,
    required this.levels,
    required this.direct,
    required this.network,
    required this.earned,
    required this.pending,
    required this.karma,
    required this.canClaim,
    required this.invites,
    required this.history,
    this.invitedBy,
  });

  final bool enabled;
  final String code;
  final List<int> levelPoints;

  /// Сколько людей на каждом уровне сети: {1: 3, 2: 7, …}.
  final Map<int, int> levels;
  final int direct;
  final int network;
  final int earned;
  final int pending;
  final int karma;
  final bool canClaim;
  final String? invitedBy;
  final List<InviteEntry> invites;
  final List<PointTx> history;

  Uri get link => InviteLinks.shareUri(code);

  factory ReferralOverview.fromJson(Map<String, dynamic> j) => ReferralOverview(
    enabled: j['enabled'] != false,
    code: j['code'] as String,
    levelPoints: [for (final p in (j['level_points'] as List? ?? const [])) (p as num).toInt()],
    levels: {
      for (final l in (j['levels'] as List? ?? const []))
        ((l as Map)['level'] as num).toInt(): (l['count'] as num).toInt(),
    },
    direct: (j['direct'] as num?)?.toInt() ?? 0,
    network: (j['network'] as num?)?.toInt() ?? 0,
    earned: (j['earned'] as num?)?.toInt() ?? 0,
    pending: (j['pending'] as num?)?.toInt() ?? 0,
    karma: (j['karma'] as num?)?.toInt() ?? 0,
    canClaim: j['can_claim'] == true,
    invitedBy: (j['invited_by'] as Map?)?['name'] as String?,
    invites: [for (final i in (j['invites'] as List? ?? const [])) InviteEntry.fromJson(Map<String, dynamic>.from(i as Map))],
    history: [for (final t in (j['history'] as List? ?? const [])) PointTx.fromJson(Map<String, dynamic>.from(t as Map))],
  );
}

/// Код, пришедший до входа (ссылка или буфер обмена). Живёт в настройках
/// телефона: переживает установку → первый запуск → регистрацию.
abstract final class PendingInvite {
  static const _codeKey = 'invites.pending_code';
  static const _sourceKey = 'invites.pending_source';
  static const _clipboardKey = 'invites.clipboard_checked';

  static Future<void> save(String code, String source) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_codeKey, code);
    await prefs.setString(_sourceKey, source);
  }

  static Future<({String code, String source})?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_codeKey);
    if (code == null) return null;
    return (code: code, source: prefs.getString(_sourceKey) ?? 'link');
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_codeKey);
    await prefs.remove(_sourceKey);
  }

  /// Буфер обмена смотрим один раз за установку: Android показывает человеку
  /// «приложение прочитало буфер», и делать это на каждом запуске — дурной тон.
  static Future<String?> takeFromClipboardOnce() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_clipboardKey) ?? false) return null;
    await prefs.setBool(_clipboardKey, true);
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      return InviteLinks.fromClipboard(data?.text);
    } catch (error) {
      AppLog.add('Буфер обмена не прочитался: $error');
      return null;
    }
  }
}

/// Хеш Android ID: тот же телефон узнаётся и после переустановки, а сам
/// идентификатор на сервер не уходит.
abstract final class DeviceFingerprint {
  static const _channel = MethodChannel('chawo/device');
  static String? _cached;

  static Future<String?> get() async {
    if (_cached != null) return _cached;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      final id = await _channel.invokeMethod<String>('androidId');
      if (id == null || id.isEmpty) return null;
      return _cached = sha256.convert(utf8.encode('chawo-device:$id')).toString();
    } catch (error) {
      AppLog.add('Отпечаток устройства: $error');
      return null;
    }
  }
}

class InviteRepository {
  InviteRepository(this._client);

  final SupabaseClient _client;

  Future<ReferralOverview> load() async {
    final raw = await _client.rpc('my_referral');
    return ReferralOverview.fromJson(Map<String, dynamic>.from(raw as Map));
  }

  /// Указать пригласившего. Возвращает имя пригласившего.
  Future<String?> claim(String code, {required String source}) async {
    final raw = await _client.rpc(
      'claim_referral',
      params: {'in_code': code, 'in_device': await DeviceFingerprint.get(), 'in_source': source},
    );
    return (raw as Map?)?['inviter_name'] as String?;
  }

  Future<void> reportDevice() async {
    final device = await DeviceFingerprint.get();
    if (device == null) return;
    await _client.rpc('report_device', params: {'in_device': device});
  }

  /// Событие воронки (сервер принимает только referral_* и activity_points_*).
  Future<void> track(String name, [Map<String, Object?> props = const {}]) async {
    try {
      await _client.rpc('track_event', params: {'in_name': name, 'in_props': props});
    } catch (error) {
      AppLog.add('Событие $name не записалось: $error');
    }
  }
}

final inviteRepositoryProvider = Provider<InviteRepository?>((ref) {
  if (!Env.isConfigured) return null;
  return InviteRepository(Supabase.instance.client);
});

final referralOverviewProvider = FutureProvider.autoDispose<ReferralOverview?>((ref) async {
  final repo = ref.watch(inviteRepositoryProvider);
  return repo?.load();
});
