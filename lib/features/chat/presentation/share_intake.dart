import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/debug/app_log.dart';
import '../../../core/router/app_router.dart';
import '../../../core/share/incoming_share.dart';
import '../data/chat_media_cache.dart';
import '../domain/entities/chat_message.dart';
import 'providers/chat_providers.dart';
import 'widgets/forward_picker.dart';

const _uuid = Uuid();

MessageKind _kindOf(SharedFile file) => file.isImage
    ? MessageKind.image
    : file.isVideo
    ? MessageKind.video
    : MessageKind.file;

/// Присланное из другого приложения → сообщения, которые уходят существующей
/// пересылкой. Файлы сначала кладутся в кэш чата под id сообщения: именно оттуда
/// пересылка берёт файл, а не скачивает его с сервера.
///
/// Несколько фото — один альбом (пересылка сама режет по 8); подпись, если она
/// есть, достаётся первому медиа; текст без файлов — обычное сообщение.
Future<List<ChatMessage>> buildShareMessages(
  IncomingShare share, {
  String Function()? newId,
  Future<void> Function(String id, MessageKind kind, SharedFile file)? keep,
}) async {
  final nextId = newId ?? () => 'share-${_uuid.v4()}';
  final remember = keep ??
      (String id, MessageKind kind, SharedFile file) =>
          ChatMediaCache.keepSent(id, kind, file.path, file.name);

  ChatMessage message(String id, MessageKind kind, {String? text, ChatAttachment? attachment}) =>
      ChatMessage(
        id: id,
        conversationId: '',
        senderId: '',
        sentAt: DateTime.now(),
        kind: kind,
        text: text,
        attachment: attachment,
      );

  ChatAttachment attachmentOf(SharedFile file, {List<ChatAttachment> album = const []}) =>
      ChatAttachment(
        path: '',
        size: file.size,
        name: file.name,
        mime: file.mime,
        album: album,
      );

  final out = <ChatMessage>[];
  var caption = share.text;
  String? takeCaption() {
    final value = caption;
    caption = null;
    return value;
  }

  final images = [for (final f in share.files) if (f.isImage) f];
  final others = [for (final f in share.files) if (!f.isImage) f];

  if (images.length == 1) {
    final id = nextId();
    await remember(id, MessageKind.image, images.first);
    out.add(message(id, MessageKind.image, text: takeCaption(), attachment: attachmentOf(images.first)));
  } else if (images.length > 1) {
    final id = nextId();
    for (var i = 0; i < images.length; i++) {
      await remember(i == 0 ? id : '$id-a$i', MessageKind.image, images[i]);
    }
    out.add(
      message(
        id,
        MessageKind.image,
        text: takeCaption(),
        attachment: attachmentOf(
          images.first,
          album: [for (final f in images.skip(1)) attachmentOf(f)],
        ),
      ),
    );
  }

  for (final file in others) {
    final id = nextId();
    final kind = _kindOf(file);
    await remember(id, kind, file);
    out.add(message(id, kind, text: takeCaption(), attachment: attachmentOf(file)));
  }

  final leftover = takeCaption();
  if (leftover != null) out.add(message(nextId(), MessageKind.text, text: leftover));
  return out;
}

/// Показывает выбор чата для присланного из другого приложения и отправляет.
/// После отправки открывает единственный выбранный чат.
Future<void> handleIncomingShare(BuildContext context, WidgetRef ref, IncomingShare share) async {
  final messenger = ScaffoldMessenger.of(context);
  final router = GoRouter.of(context);
  if (share.files.isEmpty && (share.text == null)) {
    if (share.skipped > 0) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Файл слишком большой: в чат можно отправить до 50 МБ')),
      );
    }
    return;
  }
  try {
    final messages = await buildShareMessages(share);
    if (!context.mounted) return;
    final result = await showForwardPicker(
      context,
      messages: messages,
      authorOf: (_) => '',
      withAuthor: false,
      title: 'Отправить в ChaWo',
    );
    if (result == null) return;
    final all = ref.read(conversationsProvider).value ?? const [];
    messenger.showSnackBar(SnackBar(content: Text(forwardSummary(result, all))));
    if (result.delivered.length == 1) {
      router.go('${Routes.chats}/${result.delivered.first}');
    }
  } catch (error) {
    AppLog.add('Отправка присланного: $error');
    messenger.showSnackBar(const SnackBar(content: Text('Не удалось отправить')));
  } finally {
    if (share.skipped > 0) {
      messenger.showSnackBar(
        SnackBar(content: Text('Не взяли файлов: ${share.skipped} (слишком большие)')),
      );
    }
  }
}
