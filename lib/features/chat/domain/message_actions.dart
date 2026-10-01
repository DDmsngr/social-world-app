import 'entities/chat_message.dart';

/// Пункты меню сообщения (долгий тап) и «⋮» в просмотре фото из чата.
enum MessageAction { reply, copy, saveToGallery, share, forward, delete }

/// Что можно сделать с сообщением. Одно место для правил: его читают меню,
/// просмотрщик и подсказки для экранного чтеца.
///
/// [canReply] — в чат можно писать (в закрытом квест-чате отвечать некуда).
List<MessageAction> messageActions(
  ChatMessage message, {
  bool canReply = true,
}) {
  final text = message.text?.trim() ?? '';
  final attachment = message.attachment;
  final media =
      attachment != null &&
      switch (message.kind) {
        MessageKind.image || MessageKind.video || MessageKind.videoNote => true,
        _ => false,
      };
  // Сообщение, которое не расшифровалось или не прошло проверку подписи,
  // нельзя ни цитировать, ни пересылать: там нет достоверного содержимого.
  final trusted =
      message.signatureValid != false && message.status != MessageStatus.failed;
  return [
    if (canReply && trusted) MessageAction.reply,
    if (text.isNotEmpty) MessageAction.copy,
    if (media) MessageAction.saveToGallery,
    if (attachment != null && message.kind != MessageKind.sticker)
      MessageAction.share,
    if (trusted) MessageAction.forward,
    MessageAction.delete,
  ];
}

/// Можно ли удалить у всех: своё — всегда, чужое — только владельцу группы.
/// Чужое в личном диалоге — только скрыть у себя. Сервер проверяет то же
/// самое (delete_chat_messages, миграция 0033).
bool canDeleteForEveryone(
  ChatMessage message, {
  required String myId,
  required bool isDirect,
  required bool isGroupOwner,
}) => message.senderId == myId || (!isDirect && isGroupOwner);
