import 'package:flutter_test/flutter_test.dart';
import 'package:social_world/features/chat/data/crypto/chat_crypto_service.dart';
import 'package:social_world/features/chat/data/crypto/chat_key_backup.dart';
import 'package:social_world/features/chat/data/crypto/chat_key_storage.dart';

class _MemoryBackup implements ChatKeyBackup {
  final rows = <String, ChatKeySeeds>{};
  var saves = 0;
  var offline = false;

  @override
  Future<ChatKeySeeds?> fetch(String userId) async {
    if (offline) throw Exception('нет сети');
    return rows[userId];
  }

  @override
  Future<void> save(String userId, ChatKeySeeds seeds) async {
    if (offline) throw Exception('нет сети');
    saves++;
    rows[userId] = seeds;
  }
}

Future<String> _publicKey(ChatKeyStorage storage) async =>
    (await (await ChatCryptoService.initialize(userId: 'me', storage: storage)).publicKeys).exchangeKey;

void main() {
  test('первый вход: ключи созданы и копия легла на сервер', () async {
    final storage = MemoryChatKeyStorage();
    final backup = _MemoryBackup();
    await syncChatKeys(userId: 'me', storage: storage, backup: backup);
    expect(await ChatCryptoService.hasKeys(userId: 'me', storage: storage), isTrue);
    expect(backup.rows['me'], isNotNull);
  });

  test('переустановка: на телефоне пусто — ключ возвращается из копии, тот же самый', () async {
    final backup = _MemoryBackup();
    final oldPhone = MemoryChatKeyStorage();
    await syncChatKeys(userId: 'me', storage: oldPhone, backup: backup);
    final before = await _publicKey(oldPhone);

    final reinstalled = MemoryChatKeyStorage();
    await syncChatKeys(userId: 'me', storage: reinstalled, backup: backup);
    expect(await _publicKey(reinstalled), before);
  });

  test('ключи на телефоне были до копий: кладём их, и только один раз', () async {
    final storage = MemoryChatKeyStorage();
    final key = await _publicKey(storage);
    final backup = _MemoryBackup();
    await syncChatKeys(userId: 'me', storage: storage, backup: backup);
    await syncChatKeys(userId: 'me', storage: storage, backup: backup);
    expect(backup.saves, 1);
    expect(await _publicKey(storage), key);
  });

  test('ключей нет и сервер недоступен — новых не создаём, ошибка наверх', () async {
    final storage = MemoryChatKeyStorage();
    final backup = _MemoryBackup()..offline = true;
    await expectLater(syncChatKeys(userId: 'me', storage: storage, backup: backup), throwsException);
    expect(await ChatCryptoService.hasKeys(userId: 'me', storage: storage), isFalse);
  });

  test('ключи есть, сервер недоступен — работаем дальше', () async {
    final storage = MemoryChatKeyStorage();
    await _publicKey(storage);
    final backup = _MemoryBackup()..offline = true;
    await syncChatKeys(userId: 'me', storage: storage, backup: backup);
    expect(await ChatCryptoService.hasKeys(userId: 'me', storage: storage), isTrue);
  });
}
