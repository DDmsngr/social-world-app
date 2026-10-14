import 'package:shared_preferences/shared_preferences.dart';

import 'chat_crypto_service.dart';

/// Ключи собеседников, увиденные впервые («доверие при первой встрече»).
///
/// Сервер раздаёт публичные ключи, и тот, у кого есть к нему доступ, мог бы
/// незаметно подставить свой ключ и читать новые сообщения. Поэтому первый
/// увиденный ключ запоминается на телефоне, а смену приложение показывает и
/// не шифрует новым ключом, пока человек сам его не примет.
///
/// Ключи публичные, секрета тут нет, поэтому хватает обычных настроек.
abstract interface class PeerKeyPins {
  Future<String?> read(String profileId);
  Future<void> write(String profileId, String fingerprint);

  /// Прежние ключи собеседника, которые мы приняли и потом сменили. По ним
  /// телефон расшифровывает старую переписку, чтобы переложить её под новый
  /// ключ собеседника (миграция 0084).
  Future<List<String>> previous(String profileId);
  Future<void> rememberPrevious(String profileId, String fingerprint);

  /// Переписка с этим ключом собеседника уже переложена.
  Future<bool> rekeyed(String profileId, String fingerprint);
  Future<void> markRekeyed(String profileId, String fingerprint);
}

String peerKeyFingerprint(ChatPublicKeys keys) =>
    '${keys.exchangeKey}|${keys.signingKey}';

class PrefsPeerKeyPins implements PeerKeyPins {
  const PrefsPeerKeyPins();

  static String _key(String profileId) => 'peer_key_pin:$profileId';

  @override
  Future<String?> read(String profileId) async =>
      (await SharedPreferences.getInstance()).getString(_key(profileId));

  @override
  Future<void> write(String profileId, String fingerprint) async {
    await (await SharedPreferences.getInstance()).setString(_key(profileId), fingerprint);
  }

  static String _previousKey(String profileId) => 'peer_key_prev:$profileId';
  static String _rekeyedKey(String profileId) => 'peer_key_rekeyed:$profileId';

  @override
  Future<List<String>> previous(String profileId) async =>
      (await SharedPreferences.getInstance()).getStringList(_previousKey(profileId)) ?? const [];

  @override
  Future<void> rememberPrevious(String profileId, String fingerprint) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_previousKey(profileId)) ?? <String>[];
    if (!list.contains(fingerprint)) await prefs.setStringList(_previousKey(profileId), [...list, fingerprint]);
  }

  @override
  Future<bool> rekeyed(String profileId, String fingerprint) async =>
      (await SharedPreferences.getInstance()).getStringList(_rekeyedKey(profileId))?.contains(fingerprint) ?? false;

  @override
  Future<void> markRekeyed(String profileId, String fingerprint) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_rekeyedKey(profileId)) ?? <String>[];
    if (!list.contains(fingerprint)) await prefs.setStringList(_rekeyedKey(profileId), [...list, fingerprint]);
  }
}

class MemoryPeerKeyPins implements PeerKeyPins {
  final _pins = <String, String>{};
  final _previous = <String, List<String>>{};
  final _rekeyed = <String, Set<String>>{};

  @override
  Future<List<String>> previous(String profileId) async => _previous[profileId] ?? const [];

  @override
  Future<void> rememberPrevious(String profileId, String fingerprint) async {
    final list = _previous.putIfAbsent(profileId, () => []);
    if (!list.contains(fingerprint)) list.add(fingerprint);
  }

  @override
  Future<bool> rekeyed(String profileId, String fingerprint) async =>
      _rekeyed[profileId]?.contains(fingerprint) ?? false;

  @override
  Future<void> markRekeyed(String profileId, String fingerprint) async =>
      _rekeyed.putIfAbsent(profileId, () => {}).add(fingerprint);

  @override
  Future<String?> read(String profileId) async => _pins[profileId];

  @override
  Future<void> write(String profileId, String fingerprint) async {
    _pins[profileId] = fingerprint;
  }
}

/// Ключ собеседника сменился, а человек новый ещё не принял.
class PeerKeyChangedException implements Exception {
  const PeerKeyChangedException();

  String get message =>
      'Ключ шифрования собеседника сменился. Откройте «Код безопасности», '
      'сверьте код и примите новый ключ';

  @override
  String toString() => message;
}
