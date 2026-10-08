import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/link_text.dart';
import '../../../channels/presentation/widgets/channel_media.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/chat_meta.dart';
import 'attachment_views.dart';
import 'emoji_panel.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.mine,
    this.showSender = false,
    this.onMediaMore,
    this.onQuoteTap,
  });

  final ChatMessage message;
  final bool mine;

  /// В группах над чужим сообщением — имя автора.
  final bool showSender;

  /// Меню из полноэкранного просмотра фото.
  final Future<bool> Function(BuildContext context)? onMediaMore;

  /// Тап по цитате — к сообщению, на которое ответили.
  final VoidCallback? onQuoteTap;

  @override
  Widget build(BuildContext context) {
    final radius = Radius.circular(AppRadius.card);
    // Сообщение из 1–3 эмодзи рисуется крупно и без пузыря, как в Telegram.
    // Старые «стикеры» — это тоже эмодзи, показываются так же.
    final emojiCount = switch (message.kind) {
      MessageKind.text => emojiOnlyCount(message.text),
      MessageKind.sticker => 1,
      _ => 0,
    };
    // С ответом или пересылкой сообщению нужен пузырь: в нём живёт цитата.
    final hasMeta = message.replyTo != null || message.forwardedFrom != null;
    final bigEmoji = emojiCount > 0 && !hasMeta;
    final bare =
        bigEmoji ||
        (!hasMeta &&
            message.kind == MessageKind.videoNote &&
            message.attachment != null);
    final caption = message.text?.trim() ?? '';
    final hasAttachment =
        message.attachment != null && message.kind != MessageKind.sticker;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showSender && message.senderName != null)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                message.senderName!,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryTint,
                ),
              ),
            ),
          ),
        if (message.forwardedFrom != null)
          _ForwardedLabel(name: message.forwardedFrom!, mine: mine),
        if (message.replyTo != null)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onQuoteTap,
            child: _QuoteBlock(reply: message.replyTo!, mine: mine),
          ),
        if (bigEmoji)
          Text(
            caption,
            style: TextStyle(
              fontSize: switch (emojiCount) {
                1 => 56,
                2 => 44,
                _ => 36,
              },
              height: 1.1,
            ),
          )
        else if (hasAttachment && message.attachment!.album.isNotEmpty)
          // Несколько фото одним сообщением: сетка по пропорциям кадров.
          SizedBox(
            width: 260,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: MessageAlbum(message: message),
            ),
          )
        else if (hasAttachment)
          AttachmentView(message: message, mine: mine, onMore: onMediaMore),
        if (!bare && (!hasAttachment || caption.isNotEmpty)) ...[
          if (hasAttachment) const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: LinkText(
              caption.isEmpty && !hasAttachment ? message.preview : caption,
              linkColor: mine ? AppColors.onBubbleMine : AppColors.primaryTint,
              style: TextStyle(
                fontSize: 15,
                height: 1.4,
                color: mine ? AppColors.onBubbleMine : AppColors.text,
              ),
            ),
          ),
        ],
        const SizedBox(height: 4),
        _Meta(message: message, mine: mine, onBubble: !bare),
      ],
    );

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: bare
            ? EdgeInsets.zero
            : hasAttachment
            ? const EdgeInsets.fromLTRB(6, 6, 10, 6)
            : const EdgeInsets.fromLTRB(14, 10, 14, 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        decoration: bare
            ? null
            : BoxDecoration(
                color: mine ? AppColors.bubbleMine : AppColors.card,
                border: mine ? null : Border.all(color: AppColors.hair),
                borderRadius: BorderRadius.only(
                  topLeft: radius,
                  topRight: radius,
                  bottomLeft: mine ? radius : const Radius.circular(4),
                  bottomRight: mine ? const Radius.circular(4) : radius,
                ),
              ),
        child: content,
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({
    required this.message,
    required this.mine,
    required this.onBubble,
  });

  final ChatMessage message;
  final bool mine;

  /// На цветном пузыре — светлые подписи; без пузыря — обычные.
  final bool onBubble;

  @override
  Widget build(BuildContext context) {
    final color = mine && onBubble
        ? AppColors.onBubbleMine.withValues(alpha: 0.6)
        : AppColors.textFaint;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Подделанную подпись нельзя показывать как обычное сообщение.
        if (message.signatureValid == false) ...[
          Icon(Icons.gpp_maybe_outlined, size: 13, color: AppColors.danger),
          const SizedBox(width: 4),
          Text(
            'подпись не сходится',
            style: TextStyle(fontSize: 11, color: AppColors.danger),
          ),
          const SizedBox(width: 8),
        ],
        // Изменённое — карандаш у времени, как в Telegram.
        if (message.editedAt != null) ...[
          Icon(Icons.edit, size: 11, color: color),
          const SizedBox(width: 3),
        ],
        Text(
          _time(message.sentAt),
          style: TextStyle(fontSize: 11, color: color),
        ),
        if (mine) ...[
          const SizedBox(width: 4),
          Icon(
            message.status == MessageStatus.read ? Icons.done_all : Icons.done,
            size: 13,
            // Прочитанное — единственное место с акцентом в пузыре.
            color: message.status == MessageStatus.read
                ? AppColors.primaryTint
                : color,
          ),
        ],
      ],
    );
  }

  String _time(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}

/// «Переслано от …» над содержимым.
class _ForwardedLabel extends StatelessWidget {
  const _ForwardedLabel({required this.name, required this.mine});

  final String name;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shortcut_rounded, size: 14, color: AppColors.primaryTint),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                'Переслано от $name',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: AppColors.primaryTint,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Цитата сообщения, на которое это — ответ.
class _QuoteBlock extends StatelessWidget {
  const _QuoteBlock({required this.reply, required this.mine});

  final ChatReply reply;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final dim = mine
        ? AppColors.onBubbleMine.withValues(alpha: 0.75)
        : AppColors.textDim;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 4, 8, 4),
      decoration: BoxDecoration(
        color: AppColors.ink.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: AppColors.primaryTint, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            reply.senderName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryTint,
            ),
          ),
          Text(
            reply.preview,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: dim),
          ),
        ],
      ),
    );
  }
}
