import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

/// Загрузка фотографий и видео в Supabase Storage.
///
/// Путь всегда начинается с id пользователя: политика бакета разрешает запись
/// только в свою папку, так что чужое имя в пути просто не пройдёт.
class MediaUploader {
  MediaUploader(this._client, {required this.bucket});

  final SupabaseClient _client;
  final String bucket;

  static const _uuid = Uuid();

  Future<String> upload(String localPath) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw const AuthException('Нет активной сессии');

    final dot = localPath.lastIndexOf('.');
    final extension = dot == -1 ? '.jpg' : localPath.substring(dot).toLowerCase();
    final objectPath = '$userId/${_uuid.v4()}$extension';

    await _client.storage
        .from(bucket)
        .upload(
          objectPath,
          File(localPath),
          fileOptions: const FileOptions(cacheControl: '31536000'),
        );

    return _client.storage.from(bucket).getPublicUrl(objectPath);
  }
}
