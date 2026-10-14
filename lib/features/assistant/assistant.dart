import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/env.dart';
import '../../core/debug/app_log.dart';
import '../../core/widgets/user_avatar.dart';
import '../auth/presentation/providers/auth_providers.dart';

/// Чат «Помощник» у владельца проекта или «Для багов» у тестировщика
/// (миграция 0086): одна таблица, разные каналы.
enum AssistantChannel {
  assistant('assistant'),
  bugs('bugs');

  const AssistantChannel(this.wire);

  final String wire;
}

/// Сообщение в чате «Помощник»: либо от человека, либо ответ Claude из сессии.
class AssistantMessage {
  const AssistantMessage({
    required this.id,
    required this.fromUser,
    required this.createdAt,
    this.body,
    this.attachmentPath,
    this.handledAt,
  });

  final String id;
  final bool fromUser;
  final String? body;
  final String? attachmentPath;
  final DateTime createdAt;

  /// Когда Помощник забрал сообщение; `null` — ещё нет.
  final DateTime? handledAt;

  factory AssistantMessage.fromRow(Map<String, dynamic> row) => AssistantMessage(
    id: row['id'] as String,
    fromUser: row['from_user'] as bool,
    body: row['body'] as String?,
    attachmentPath: row['attachment_path'] as String?,
    createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
    handledAt: row['handled_at'] == null
        ? null
        : DateTime.parse(row['handled_at'] as String).toLocal(),
  );
}

class AssistantRepository {
  AssistantRepository(this._client);

  final SupabaseClient _client;

  static const bucket = 'assistant';

  Future<bool> isOwner() async =>
      (await _client.rpc('is_assistant_owner')) == true;

  /// Кем человек приходится проекту. До миграции 0086 функции нет — тогда
  /// спрашиваем по-старому, только про владельца.
  Future<({bool owner, bool tester})> roles() async {
    try {
      final raw = Map<String, dynamic>.from(await _client.rpc('my_app_roles') as Map);
      return (owner: raw['owner'] == true, tester: raw['tester'] == true);
    } on PostgrestException {
      return (owner: await isOwner(), tester: false);
    }
  }

  /// Назначить или снять тестировщика — только владелец (проверяет сервер).
  Future<void> setTester(String profileId, bool on) =>
      _client.rpc('set_app_tester', params: {'in_profile': profileId, 'in_on': on});

  Future<bool> isTester(String profileId) async =>
      (await _client.rpc('is_profile_tester', params: {'in_profile': profileId})) == true;

  Stream<List<AssistantMessage>> watch(AssistantChannel channel) => _client
      .from('assistant_messages')
      .stream(primaryKey: ['id'])
      .eq('channel', channel.wire)
      .order('created_at')
      .map(
        (rows) => [for (final row in rows) AssistantMessage.fromRow(row)]
          // Новые строки из реалтайма приходят в конец списка как есть — порядок
          // по времени наводим сами.
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
      );

  /// [imagePath] — локальный файл скриншота, если он приложен.
  Future<void> send({
    String? text,
    String? imagePath,
    AssistantChannel channel = AssistantChannel.assistant,
  }) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw const AuthException('Нет активной сессии');

    String? remote;
    if (imagePath != null) {
      final dot = imagePath.lastIndexOf('.');
      final ext = dot == -1 ? 'jpg' : imagePath.substring(dot + 1).toLowerCase();
      remote = '$uid/${DateTime.now().millisecondsSinceEpoch}.$ext';
      // Видео и голосовые бывают большими — файлом, а не байтами в памяти.
      await _client.storage.from(bucket).upload(remote, File(imagePath));
    }
    final body = text?.trim();
    await _client.from('assistant_messages').insert({
      'from_user': true,
      if (channel == AssistantChannel.bugs) ...{'channel': channel.wire, 'author_id': uid},
      'body': body == null || body.isEmpty ? null : body,
      'attachment_path': remote,
    });
  }

  /// Правка и удаление — только пока сообщение «ждёт»; это проверяет сервер.
  Future<void> edit(String id, String text) async {
    final body = text.trim();
    if (body.isEmpty) return delete(id);
    final rows = await _client
        .from('assistant_messages')
        .update({'body': body})
        .eq('id', id)
        .select('id');
    if ((rows as List).isEmpty) throw StateError('Сообщение уже забрано');
  }

  Future<void> delete(String id) async {
    final rows = await _client.from('assistant_messages').delete().eq('id', id).select('id');
    if ((rows as List).isEmpty) throw StateError('Сообщение уже забрано');
  }

  Future<String> signedUrl(String path) =>
      _client.storage.from(bucket).createSignedUrl(path, 3600);
}

final assistantRepositoryProvider = Provider<AssistantRepository?>((ref) {
  ref.keepAlive();
  if (!Env.isConfigured) return null;
  return AssistantRepository(Supabase.instance.client);
});

/// Роли человека в проекте: владелец видит «Помощник», тестировщик — «Для
/// багов». Решает сервер.
final appRolesProvider = FutureProvider<({bool owner, bool tester})>((ref) async {
  ref.keepAlive();
  final repo = ref.watch(assistantRepositoryProvider);
  if (repo == null || ref.watch(currentUserProvider) == null) return (owner: false, tester: false);
  try {
    return await repo.roles();
  } catch (error) {
    AppLog.add('Проверка ролей не прошла: $error');
    return (owner: false, tester: false);
  }
});

/// Показывать ли чат «Помощник»: только аккаунту-владельцу.
final isAssistantOwnerProvider = FutureProvider<bool>(
  (ref) async => (await ref.watch(appRolesProvider.future)).owner,
);

/// Показывать ли «Для багов»: только тестировщику.
final isTesterProvider = FutureProvider<bool>(
  (ref) async => (await ref.watch(appRolesProvider.future)).tester,
);

final assistantMessagesProvider =
    StreamProvider.autoDispose.family<List<AssistantMessage>, AssistantChannel>((ref, channel) {
      final repo = ref.watch(assistantRepositoryProvider);
      if (repo == null) return const Stream.empty();
      return repo.watch(channel);
    });

/// Кто с каймой у аватара (команда, тестировщики, 0087). Без миграции или
/// сети — без каймы.
Future<void> reloadAvatarRings() async {
  if (!Env.isConfigured) return;
  try {
    final rows = await Supabase.instance.client.rpc('profile_rings') as List;
    AvatarRings.set([for (final row in rows) Map<String, dynamic>.from(row as Map)]);
  } catch (error) {
    AppLog.add('Каймы аватаров не загрузились: $error');
  }
}
