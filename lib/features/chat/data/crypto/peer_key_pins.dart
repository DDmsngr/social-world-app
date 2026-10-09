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
}

class MemoryPeerKeyPins implements PeerKeyPins {
  final _pins = <String, String>{};

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
