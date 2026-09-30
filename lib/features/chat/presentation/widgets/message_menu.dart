import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/debug/app_log.dart';
import '../../../../core/errors/friendly_error.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/message_actions.dart';
import '../../domain/repositories/chat_repository.dart';
import '../providers/chat_providers.dart';
import '../providers/hidden_messages_provider.dart';

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
}) async {
  HapticFeedback.mediumImpact();
  final actions = messageActions(message);
  final action = await showModalBottomSheet<MessageAction>(
    context: context,
    useRootNavigator: true,
    backgroundColor: AppColors.ink2,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final action in actions) ...[
            // Разрушительное — отдельно и последним, чтобы по нему не
            // попадали вместо соседнего пункта.
            if (action == MessageAction.delete && actions.length > 1)
              Divider(height: 12, color: AppColors.hair),
            ListTile(
              leading: Icon(
                _icon(action),
                color: action == MessageAction.delete
                    ? AppColors.danger
                    : AppColors.textDim,
              ),
              title: Text(
                _label(action),
                style: action == MessageAction.delete
                    ? TextStyle(color: AppColors.danger)
                    : null,
              ),
              onTap: () => Navigator.of(context).pop(action),
            ),
          ],
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return false;

  final messenger = ScaffoldMessenger.of(context);
  final repository = ref.read(chatRepositoryProvider);
  switch (action) {
    case MessageAction.copy:
      await Clipboard.setData(ClipboardData(text: message.text!.trim()));
      messenger.showSnackBar(const SnackBar(content: Text('Скопировано')));
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

String _label(MessageAction action) => switch (action) {
  MessageAction.copy => 'Копировать',
  MessageAction.saveToGallery => 'Сохранить в галерею',
  MessageAction.share => 'Поделиться',
  MessageAction.delete => 'Удалить',
};

IconData _icon(MessageAction action) => switch (action) {
  MessageAction.copy => Icons.copy_rounded,
  MessageAction.saveToGallery => Icons.download_rounded,
  MessageAction.share => Icons.ios_share_rounded,
  MessageAction.delete => Icons.delete_outline_rounded,
};

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
    final deleted = await ref
        .read(chatRepositoryProvider)
        .deleteForEveryone([message]);
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
        activeColor: AppColors.champagne,
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
