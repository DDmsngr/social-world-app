import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class ChatKeyStorage {
  Future<String?> read(String key);

  Future<void> write(String key, String value);
}

/// Private identity keys are wrapped by Android Keystore or stored in iOS
/// Keychain. The web implementation of the plugin is used only for dev builds.
class SecureChatKeyStorage implements ChatKeyStorage {
  SecureChatKeyStorage({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(
              migrateWithBackup: true,
              storageNamespace: 'social_world_chat',
            ),
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
}

class MemoryChatKeyStorage implements ChatKeyStorage {
  final _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }
}
