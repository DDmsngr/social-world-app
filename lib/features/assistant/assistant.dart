import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/env.dart';
import '../../core/debug/app_log.dart';
import '../auth/presentation/providers/auth_providers.dart';

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

  Stream<List<AssistantMessage>> watch() => _client
      .from('assistant_messages')
      .stream(primaryKey: ['id'])
      .order('created_at')
      .map(
        (rows) => [for (final row in rows) AssistantMessage.fromRow(row)]
          // Новые строки из реалтайма приходят в конец списка как есть — порядок
          // по времени наводим сами.
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
      );

  /// [imagePath] — локальный файл скриншота, если он приложен.
  Future<void> send({String? text, String? imagePath}) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw const AuthException('Нет активной сессии');

    String? remote;
    if (imagePath != null) {
      final dot = imagePath.lastIndexOf('.');
      final ext = dot == -1 ? 'jpg' : imagePath.substring(dot + 1).toLowerCase();
      remote = '$uid/${DateTime.now().millisecondsSinceEpoch}.$ext';
      await _client.storage
          .from(bucket)
          .uploadBinary(remote, await File(imagePath).readAsBytes());
    }
    final body = text?.trim();
    await _client.from('assistant_messages').insert({
      'from_user': true,
      'body': body == null || body.isEmpty ? null : body,
      'attachment_path': remote,
    });
  }

  Future<String> signedUrl(String path) =>
      _client.storage.from(bucket).createSignedUrl(path, 3600);
}

final assistantRepositoryProvider = Provider<AssistantRepository?>((ref) {
  ref.keepAlive();
  if (!Env.isConfigured) return null;
  return AssistantRepository(Supabase.instance.client);
});

/// Показывать ли чат «Помощник»: только аккаунту-владельцу, это решает сервер.
final isAssistantOwnerProvider = FutureProvider<bool>((ref) async {
  ref.keepAlive();
  final repo = ref.watch(assistantRepositoryProvider);
  if (repo == null || ref.watch(currentUserProvider) == null) return false;
  try {
    return await repo.isOwner();
  } catch (error) {
    AppLog.add('Проверка «Помощника» не прошла: $error');
    return false;
  }
});

final assistantMessagesProvider =
    StreamProvider.autoDispose<List<AssistantMessage>>((ref) {
      final repo = ref.watch(assistantRepositoryProvider);
      if (repo == null) return const Stream.empty();
      return repo.watch();
    });
