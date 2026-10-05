import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/debug/app_log.dart';
import '../../../../core/errors/friendly_error.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/forward_service.dart';
import '../../domain/message_actions.dart';
import '../../domain/repositories/chat_repository.dart';
import '../providers/chat_providers.dart';
import '../providers/hidden_messages_provider.dart';
import '../providers/chat_extras_providers.dart';
import 'forward_picker.dart';

/// Меню сообщения: долгий тап в переписке и «⋮» в просмотре фото.
///
/// Возвращает true, если сообщение пропало с экрана (удалено или скрыто) —
/// тогда просмотрщик закрывается сам.
Future<bool> showMessageMenu(
  BuildContext context,
  WidgetRef ref, {
  required ChatMessage message,
  required String myId,
  required Conversation? conversation,
  void Function(ChatMessage message)? onReply,
  // Реакции: текущая моя и что делать при выборе. Без [onReact] полосы нет
  // (просмотр фото, неотправленное сообщение).
  String? myReaction,
  void Function(String emoji)? onReact,
}) async {
  HapticFeedback.mediumImpact();
  final actions = messageActions(
    message,
    canReply: onReply != null && !(conversation?.closed ?? false),
  );
  // Плавающая панель у самого сообщения, как в Telegram: сверху реакции,
  // под ними пункты. Само сообщение остаётся подсвеченным на экране.
  final picked = await _showFloating(
    context,
    mine: message.senderId == myId,
    myReaction: myReaction,
    withReactions: onReact != null,
    actions: actions,
  );
  if (picked is _Reaction) {
    onReact?.call(picked.emoji);
    return false;
  }
  final action = picked is MessageAction ? picked : null;
  if (action == null || !context.mounted) return false;

  final messenger = ScaffoldMessenger.of(context);
  final repository = ref.read(chatRepositoryProvider);
  switch (action) {
    case MessageAction.reply:
      onReply?.call(message);
      // Из просмотра фото возвращаемся в переписку, где появилась строка ответа.
      return true;
    case MessageAction.forward:
      await _forward(context, ref, message, myId, conversation);
      return false;
    case MessageAction.copy:
      await Clipboard.setData(ClipboardData(text: message.text!.trim()));
      messenger.showSnackBar(const SnackBar(content: Text('Скопировано')));
      return false;
    case MessageAction.copyPart:
      await showDialog<void>(
        context: context,
        useRootNavigator: true,
        builder: (_) => AlertDialog(
          title: const Text('Выделите нужное'),
          content: SingleChildScrollView(
            child: SelectableText(
              message.text!.trim(),
              style: const TextStyle(fontSize: 16),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
              child: const Text('Готово'),
            ),
          ],
        ),
      );
      return false;
    case MessageAction.info:
      await _showInfo(context, message, myId: myId, conversation: conversation);
      return false;
    case MessageAction.saveToGallery:
      await _saveToGallery(messenger, repository, message);
      return false;
    case MessageAction.share:
      await _share(context, messenger, repository, message);
      return false;
    case MessageAction.delete:
      return _delete(
        context,
        ref,
        message: message,
        myId: myId,
        conversation: conversation,
      );
  }
}

/// Выбор реакции из панели — отдельный тип, чтобы не путать с пунктами меню.
class _Reaction {
  const _Reaction(this.emoji);
  final String emoji;
}

/// Короткий тап по сообщению в личной переписке: только полоса реакций у
/// сообщения, без меню. Возвращает выбранный эмодзи или null.
Future<String?> showReactionPicker(
  BuildContext context, {
  required bool mine,
  String? myReaction,
}) async {
  HapticFeedback.selectionClick();
  final picked = await _showFloating(
    context,
    mine: mine,
    myReaction: myReaction,
    withReactions: true,
    actions: const [],
    dim: false,
  );
  return picked is _Reaction ? picked.emoji : null;
}

/// Где на экране лежит сообщение: от этого прямоугольника считается, куда
/// повесить панель.
Rect? _anchorOf(BuildContext context) {
  final box = context.findRenderObject();
  if (box is RenderBox && box.attached && box.hasSize) {
    return box.localToGlobal(Offset.zero) & box.size;
  }
  return null;
}

Future<Object?> _showFloating(
  BuildContext context, {
  required bool mine,
  required String? myReaction,
  required bool withReactions,
  required List<MessageAction> actions,
  bool dim = true,
}) {
  final anchor = _anchorOf(context);
  return showGeneralDialog<Object>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    barrierLabel: 'Закрыть меню',
    barrierColor: dim ? const Color(0x59000000) : const Color(0x14000000),
    transitionDuration: const Duration(milliseconds: 140),
    pageBuilder: (dialog, _, _) => _FloatingMenu(
      anchor: anchor,
      mine: mine,
      myReaction: myReaction,
      withReactions: withReactions,
      actions: actions,
    ),
    transitionBuilder: (_, animation, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: ScaleTransition(
        scale: Tween(begin: 0.94, end: 1.0).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        ),
        child: child,
      ),
    ),
  );
}

class _FloatingMenu extends StatelessWidget {
  const _FloatingMenu({
    required this.anchor,
    required this.mine,
    required this.myReaction,
    required this.withReactions,
    required this.actions,
  });

  final Rect? anchor;
  final bool mine;
  final String? myReaction;
  final bool withReactions;
  final List<MessageAction> actions;

  static const _barHeight = 54.0;
  static const _rowHeight = 50.0;
  static const _menuWidth = 268.0;
  static const _gap = 8.0;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final size = mq.size;
    final top = mq.padding.top + 8;
    final bottom =
        size.height - (mq.padding.bottom > mq.viewInsets.bottom ? mq.padding.bottom : mq.viewInsets.bottom) - 8;

    // Просмотрщик фото отдаёт весь экран — тогда вешаем панель ближе к середине.
    var rect = anchor ?? Rect.fromLTWH(0, size.height * 0.45, size.width, 0);
    if (rect.height > size.height * 0.5) {
      rect = Rect.fromLTWH(0, size.height * 0.45, size.width, 0);
    }

    final hasDelete = actions.contains(MessageAction.delete) && actions.length > 1;
    final menuHeight = actions.isEmpty
        ? 0.0
        : actions.length * _rowHeight + (hasDelete ? 9 : 0) + 12;
    final barWidth = quickReactions.length * 44.0 + 20;

    double barTop;
    double menuTop = 0;
    if (actions.isEmpty) {
      barTop = rect.top - _barHeight - _gap;
      if (barTop < top) barTop = rect.bottom + _gap;
    } else {
      menuTop = rect.bottom + _gap;
      if (menuTop + menuHeight > bottom) menuTop = bottom - menuHeight;
      barTop = rect.top - _barHeight - _gap;
      if (barTop < top || barTop + _barHeight + _gap > menuTop) {
        barTop = menuTop - _barHeight - _gap;
      }
      if (barTop < top) {
        barTop = top;
        menuTop = barTop + _barHeight + _gap;
      }
    }

    double left(double width) => mine ? size.width - 12 - width : 12;

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          if (withReactions)
            Positioned(
              top: barTop,
              left: left(barWidth),
              child: Container(
                height: _barHeight,
                width: barWidth,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: AppColors.ink2,
                  borderRadius: BorderRadius.circular(_barHeight / 2),
                  border: Border.all(color: AppColors.hair),
                  boxShadow: const [
                    BoxShadow(color: Color(0x40000000), blurRadius: 18, offset: Offset(0, 6)),
                  ],
                ),
                child: Row(
                  children: [
                    for (final emoji in quickReactions)
                      Expanded(
                        child: Semantics(
                          button: true,
                          label: 'Реакция $emoji',
                          child: InkResponse(
                            onTap: () => Navigator.of(context).pop(_Reaction(emoji)),
                            radius: 24,
                            child: Container(
                              height: 40,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: emoji == myReaction
                                    ? AppColors.primary.withValues(alpha: 0.22)
                                    : Colors.transparent,
                              ),
                              child: Text(emoji, style: const TextStyle(fontSize: 24)),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          if (actions.isNotEmpty)
            Positioned(
              top: menuTop,
              left: left(_menuWidth),
              child: Container(
                width: _menuWidth,
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.ink2,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.hair),
                  boxShadow: const [
                    BoxShadow(color: Color(0x40000000), blurRadius: 18, offset: Offset(0, 6)),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final action in actions) ...[
                      // Разрушительное — отдельно и последним, чтобы по нему не
                      // попадали вместо соседнего пункта.
                      if (action == MessageAction.delete && actions.length > 1)
                        Divider(height: 9, thickness: 1, color: AppColors.hair),
                      InkWell(
                        onTap: () => Navigator.of(context).pop(action),
                        child: SizedBox(
                          height: _rowHeight,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _label(action),
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: action == MessageAction.delete
                                          ? AppColors.danger
                                          : AppColors.text,
                                    ),
                                  ),
                                ),
                                Icon(
                                  _icon(action),
                                  size: 22,
                                  color: action == MessageAction.delete
                                      ? AppColors.danger
                                      : AppColors.textDim,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String _label(MessageAction action) => switch (action) {
  MessageAction.reply => 'Ответить',
  MessageAction.forward => 'Переслать',
  MessageAction.copy => 'Копировать',
  MessageAction.copyPart => 'Копировать выборочно',
  MessageAction.saveToGallery => 'Сохранить в галерею',
  MessageAction.share => 'Поделиться',
  MessageAction.info => 'Свойства сообщения',
  MessageAction.delete => 'Удалить',
};

IconData _icon(MessageAction action) => switch (action) {
  MessageAction.reply => Icons.reply_rounded,
  MessageAction.forward => Icons.shortcut_rounded,
  MessageAction.copy => Icons.copy_rounded,
  MessageAction.copyPart => Icons.content_paste_search_rounded,
  MessageAction.saveToGallery => Icons.download_rounded,
  MessageAction.share => Icons.ios_share_rounded,
  MessageAction.info => Icons.info_outline_rounded,
  MessageAction.delete => Icons.delete_outline_rounded,
};

Future<void> _showInfo(
  BuildContext context,
  ChatMessage message, {
  required String myId,
  required Conversation? conversation,
}) {
  String two(int n) => n.toString().padLeft(2, '0');
  final t = message.sentAt.toLocal();
  final status = switch (message.status) {
    MessageStatus.sending => 'Отправляется',
    MessageStatus.sent => 'Отправлено',
    MessageStatus.delivered => 'Доставлено',
    MessageStatus.read => 'Прочитано',
    MessageStatus.failed => 'Не отправлено',
  };
  final size = message.attachment?.size;
  final rows = <(String, String)>[
    ('Отправлено', '${two(t.day)}.${two(t.month)}.${t.year}, ${two(t.hour)}:${two(t.minute)}'),
    ('От', message.senderId == myId ? 'Вас' : (message.senderName ?? 'Собеседника')),
    if (message.senderId == myId) ('Статус', status),
    if (message.kind != MessageKind.text) ('Тип', message.kind.preview),
    if (size != null)
      (
        'Размер файла',
        size >= 1024 * 1024
            ? '${(size / 1024 / 1024).toStringAsFixed(1)} МБ'
            : '${(size / 1024).ceil()} КБ',
      ),
    if (conversation != null)
      ('Защита', conversation.isDirect ? 'Сквозное шифрование' : 'Без сквозного шифрования'),
  ];
  return showDialog<void>(
    context: context,
    useRootNavigator: true,
    builder: (dialog) => AlertDialog(
      title: const Text('Свойства сообщения'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (name, value) in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 110,
                    child: Text(name, style: TextStyle(color: AppColors.textDim)),
                  ),
                  Expanded(child: Text(value)),
                ],
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialog).pop(),
          child: const Text('Закрыть'),
        ),
      ],
    ),
  );
}


Future<void> _forward(
  BuildContext context,
  WidgetRef ref,
  ChatMessage message,
  String myId,
  Conversation? source,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final myName = ref.read(currentUserProvider)?.displayName ?? 'Вы';
  final result = await showForwardPicker(
    context,
    messages: [message],
    excludeConversationId: message.conversationId,
    authorOf: (m) =>
        forwardAuthor(m, myId: myId, myName: myName, source: source),
  );
  if (result == null) return;
  final all = ref.read(conversationsProvider).value ?? const <Conversation>[];
  messenger.showSnackBar(SnackBar(content: Text(forwardSummary(result, all))));
}

Future<void> _saveToGallery(
  ScaffoldMessengerState messenger,
  ChatRepository repository,
  ChatMessage message,
) async {
  try {
    if (!await Gal.hasAccess() && !await Gal.requestAccess()) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Нет доступа к галерее')),
      );
      return;
    }
    // В личных чатах файл на сервере зашифрован — в галерею уходит уже
    // расшифрованная копия с устройства.
    final path = await repository.attachmentFile(message);
    if (message.kind == MessageKind.image) {
      await Gal.putImage(path, album: 'ChaWo');
    } else {
      await Gal.putVideo(path, album: 'ChaWo');
    }
    messenger.showSnackBar(
      const SnackBar(content: Text('Сохранено в галерею')),
    );
  } catch (error) {
    AppLog.add('Сохранение в галерею: $error');
    messenger.showSnackBar(
      SnackBar(
        content: Text(friendlyError(error, fallback: 'Не удалось сохранить')),
      ),
    );
  }
}

Future<void> _share(
  BuildContext context,
  ScaffoldMessengerState messenger,
  ChatRepository repository,
  ChatMessage message,
) async {
  final box = context.findRenderObject() as RenderBox?;
  final origin = box != null && box.hasSize
      ? box.localToGlobal(Offset.zero) & box.size
      : null;
  try {
    final path = await repository.attachmentFile(message);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path, mimeType: message.attachment?.mime)],
        text: message.text?.trim().isEmpty ?? true ? null : message.text,
        sharePositionOrigin: origin,
      ),
    );
  } catch (error) {
    AppLog.add('Поделиться вложением: $error');
    messenger.showSnackBar(
      SnackBar(
        content: Text(friendlyError(error, fallback: 'Не удалось поделиться')),
      ),
    );
  }
}

Future<bool> _delete(
  BuildContext context,
  WidgetRef ref, {
  required ChatMessage message,
  required String myId,
  required Conversation? conversation,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final hidden = ref.read(hiddenMessagesProvider.notifier);
  final isDirect = conversation?.isDirect ?? true;
  final everyoneAllowed = canDeleteForEveryone(
    message,
    myId: myId,
    isDirect: isDirect,
    isGroupOwner: conversation?.isOwner ?? false,
  );

  // Чужое в личном диалоге — только у себя: без диалога, но с отменой.
  final forEveryone = everyoneAllowed
      ? await showDialog<bool>(
          context: context,
          useRootNavigator: true,
          builder: (_) => _DeleteDialog(
            everyoneLabel: isDirect && conversation != null
                ? 'Удалить и у ${conversation.displayName}'
                : 'Удалить у всех участников',
          ),
        )
      : false;
  if (forEveryone == null) return false;

  hidden.hide([message.id]);
  if (!forEveryone) {
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Сообщение скрыто у вас'),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Отменить',
          onPressed: () => hidden.unhide([message.id]),
        ),
      ),
    );
    return true;
  }

  try {
    final deleted = await ref.read(chatRepositoryProvider).deleteForEveryone([
      message,
    ]);
    if (!deleted.contains(message.id)) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Удалить у всех не вышло — сообщение скрыто у вас'),
        ),
      );
    }
    ref.invalidate(conversationsProvider);
  } catch (error) {
    AppLog.add('Удаление сообщения: $error');
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          error is ChatDeleteUnavailable
              ? error.toString()
              : friendlyError(error, fallback: 'Не удалось удалить у всех'),
        ),
        action: SnackBarAction(
          label: 'Вернуть',
          onPressed: () => hidden.unhide([message.id]),
        ),
      ),
    );
  }
  return true;
}

/// «Удалить сообщение?» с галочкой «и у собеседника». Галочка включена:
/// удаляя своё, почти всегда хотят убрать его и у другого.
class _DeleteDialog extends StatefulWidget {
  const _DeleteDialog({required this.everyoneLabel});

  final String everyoneLabel;

  @override
  State<_DeleteDialog> createState() => _DeleteDialogState();
}

class _DeleteDialogState extends State<_DeleteDialog> {
  var _everyone = true;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Удалить сообщение?'),
      contentPadding: const EdgeInsets.fromLTRB(12, 16, 24, 0),
      content: CheckboxListTile(
        value: _everyone,
        onChanged: (value) => setState(() => _everyone = value ?? false),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
        activeColor: AppColors.primaryTint,
        checkColor: AppColors.ink,
        title: Text(widget.everyoneLabel),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_everyone),
          style: TextButton.styleFrom(foregroundColor: AppColors.danger),
          child: const Text('Удалить'),
        ),
      ],
    );
  }
}
