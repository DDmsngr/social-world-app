import 'entities/chat_message.dart';
import 'entities/chat_meta.dart';
import 'entities/conversation.dart';
import 'repositories/chat_repository.dart';

/// Итог пересылки: куда дошло и куда нет (с причиной).
class ForwardResult {
  const ForwardResult({this.delivered = const {}, this.failed = const {}});

  /// id чатов, куда ушли все сообщения.
  final Set<String> delivered;

  /// id чата → ошибка. В чат могло уйти не всё: пересылка этого чата
  /// остановилась на первой ошибке.
  final Map<String, Object> failed;

  bool get allDelivered => failed.isEmpty;
}

/// Чьё имя показать в «Переслано от …».
///
/// Первый автор сохраняется: пересланное пересылкой не становится «моим».
String forwardAuthor(
  ChatMessage message, {
  required String myId,
  required String myName,
  Conversation? source,
}) {
  if (message.forwardedFrom != null) return message.forwardedFrom!;
  if (message.senderId == myId) return myName;
  return message.senderName ??
      (source != null && source.isDirect ? source.peerName : null) ??
      'Пользователь';
}

/// Пересылает [messages] в каждый из [targets].
///
/// Пересылка — это обычная отправка нового сообщения от меня с пометкой об
/// авторе оригинала: у вложений в личных диалогах свой ключ, так что файл
/// скачивается, расшифровывается и шифруется заново для каждого получателя.
/// Файл при этом качается один раз, а не по разу на чат.
Future<ForwardResult> forwardMessages({
  required ChatRepository repository,
  required List<ChatMessage> messages,
  required List<Conversation> targets,
  required String Function(ChatMessage message) authorOf,
  // false — «Изменить и переслать»: уходит обычным новым сообщением, без
  // пометки «Переслано от».
  bool withAuthor = true,
}) async {
  final files = <String, String>{};
  final delivered = <String>{};
  final failed = <String, Object>{};

  for (final target in targets) {
    try {
      for (final message in messages) {
        final options = SendOptions(
          forwardedFrom: withAuthor ? authorOf(message) : null,
          sticker: message.kind == MessageKind.sticker
              ? message.stickerId
              : null,
        );
        final attachment = message.attachment;
        if (attachment == null || message.kind == MessageKind.sticker) {
          await repository.send(
            conversationId: target.id,
            text: message.text ?? '',
            kind: message.kind,
            options: options,
          );
          continue;
        }
        final path = files[message.id] ??= await repository.attachmentFile(
          message,
        );
        await repository.sendAttachment(
          conversationId: target.id,
          kind: message.kind,
          filePath: path,
          name: attachment.name,
          mime: attachment.mime,
          durationMs: attachment.durationMs,
          waveform: attachment.waveform,
          caption: message.text,
          options: options,
        );
      }
      delivered.add(target.id);
    } catch (error) {
      failed[target.id] = error;
    }
  }
  return ForwardResult(delivered: delivered, failed: failed);
}
