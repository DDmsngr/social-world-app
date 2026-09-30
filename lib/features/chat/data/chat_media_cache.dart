import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../domain/entities/chat_message.dart';

/// Расшифрованные вложения на устройстве: `<кэш>/chat_media/<id сообщения>.<ext>`.
/// Кэш, а не документы: система может его почистить, тогда файл просто
/// скачается заново.
abstract final class ChatMediaCache {
  static Future<File> fileFor(ChatMessage message) =>
      _file(message.id, message.kind, message.attachment);

  static Future<File> _file(
    String messageId,
    MessageKind kind,
    ChatAttachment? attachment,
  ) async {
    final dir = Directory(
      '${(await getApplicationCacheDirectory()).path}/chat_media',
    );
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}/$messageId${extensionFor(kind, attachment?.name)}');
  }

  /// Своё отправленное вложение кладём в кэш сразу, чтобы не скачивать его
  /// обратно с сервера.
  static Future<void> keepSent(
    String messageId,
    MessageKind kind,
    String sourcePath,
    String? name,
  ) async {
    final target = await _file(messageId, kind, ChatAttachment(
      path: '',
      size: 0,
      name: name,
    ));
    await File(sourcePath).copy(target.path);
  }

  static String extensionFor(MessageKind kind, String? name) {
    final dot = name?.lastIndexOf('.') ?? -1;
    if (name != null && dot > 0 && name.length - dot <= 6) {
      return name.substring(dot).toLowerCase();
    }
    return switch (kind) {
      MessageKind.image => '.jpg',
      MessageKind.video || MessageKind.videoNote => '.mp4',
      MessageKind.voice => '.m4a',
      _ => '',
    };
  }
}
