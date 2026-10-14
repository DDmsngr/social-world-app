import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/debug/app_log.dart';
import 'chat_crypto_service.dart';
import 'chat_key_storage.dart';

/// Закрытые ключи личных чатов (seed в base64), как они лежат в хранилище.
typedef ChatKeySeeds = ({String exchange, String signing});

/// Копия ключей на сервере (миграция 0083): после переустановки или на новом
/// телефоне ключ возвращается, и старая переписка читается.
abstract interface class ChatKeyBackup {
  Future<ChatKeySeeds?> fetch(String userId);
  Future<void> save(String userId, ChatKeySeeds seeds);
}

class SupabaseChatKeyBackup implements ChatKeyBackup {
  SupabaseChatKeyBackup(this._client);

  final SupabaseClient _client;

  @override
  Future<ChatKeySeeds?> fetch(String userId) async {
    final row = await _client
        .from('chat_key_backups')
        .select('exchange_seed, signing_seed')
        .eq('profile_id', userId)
        .maybeSingle()
        .timeout(const Duration(seconds: 15));
    if (row == null) return null;
    return (exchange: row['exchange_seed'] as String, signing: row['signing_seed'] as String);
  }

  @override
  Future<void> save(String userId, ChatKeySeeds seeds) => _client
      .from('chat_key_backups')
      .upsert({
        'profile_id': userId,
        'exchange_seed': seeds.exchange,
        'signing_seed': seeds.signing,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      })
      .timeout(const Duration(seconds: 15));
}

/// Свести ключи телефона и копию на сервере, до того как ключи понадобятся.
///
/// - На телефоне ключей нет, а копия есть — берём копию (переустановка, новый
///   телефон). Иначе были бы созданы новые ключи и старая переписка пропала бы.
/// - На телефоне ключи есть, а копии нет или она другая — кладём свои: ими
///   зашифрована переписка на этом телефоне.
///
/// Сервер не ответил — работаем с тем, что есть на телефоне. Если ключей нет и
/// копию не получить, ошибка уходит наверх: создать новые ключи сейчас значило
/// бы потерять историю, лучше повторить позже.
Future<void> syncChatKeys({
  required String userId,
  required ChatKeyStorage storage,
  required ChatKeyBackup backup,
}) async {
  final names = ChatCryptoService.storageKeyNames(userId);
  if (!await ChatCryptoService.hasKeys(userId: userId, storage: storage)) {
    ChatKeySeeds? saved;
    try {
      saved = await backup.fetch(userId);
    } on PostgrestException catch (error) {
      // Сервер ответил, но копий не умеет (миграция 0083 не накатана): как
      // раньше, просто создаём ключи. Сетевые сбои сюда не попадают.
      AppLog.add('Копия ключей недоступна: ${error.code} ${error.message}');
    }
    if (saved != null) {
      await storage.write(names.exchange, saved.exchange);
      await storage.write(names.signing, saved.signing);
      AppLog.add('Ключи переписки восстановлены из копии на сервере');
      return;
    }
    // Копии нет: это первый вход. Ключи создаёт ChatCryptoService, копия
    // уходит на сервер ниже.
    await ChatCryptoService.initialize(userId: userId, storage: storage);
  }
  final exchange = await storage.read(names.exchange);
  final signing = await storage.read(names.signing);
  if (exchange == null || signing == null) return;
  try {
    final saved = await backup.fetch(userId);
    if (saved?.exchange != exchange || saved?.signing != signing) {
      await backup.save(userId, (exchange: exchange, signing: signing));
    }
  } catch (error) {
    AppLog.add('Копия ключей переписки не сохранилась: $error');
  }
}
