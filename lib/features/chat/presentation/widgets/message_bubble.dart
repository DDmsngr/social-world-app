import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/chat_message.dart';
import 'attachment_views.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.mine,
    this.showSender = false,
  });

  final ChatMessage message;
  final bool mine;

  /// В группах над чужим сообщением — имя автора.
  final bool showSender;

  @override
  Widget build(BuildContext context) {
    final radius = Radius.circular(AppRadius.card);
    // Стикер и кружок рисуются без пузыря — как в DDChat и Telegram.
    final bare = message.kind == MessageKind.sticker ||
        (message.kind == MessageKind.videoNote && message.attachment != null);
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
        if (message.kind == MessageKind.sticker)
          Text(caption, style: const TextStyle(fontSize: 64, height: 1.1))
        else if (hasAttachment)
          AttachmentView(message: message, mine: mine),
        if (!bare && (!hasAttachment || caption.isNotEmpty)) ...[
          if (hasAttachment) const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              caption.isEmpty && !hasAttachment ? message.preview : caption,
              style: TextStyle(
                fontSize: 15,
                height: 1.4,
                color: mine ? AppColors.onPrimary : AppColors.text,
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
                color: mine ? AppColors.primary : AppColors.card,
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
        ? AppColors.onPrimary.withValues(alpha: 0.7)
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
        Text(_time(message.sentAt), style: TextStyle(fontSize: 11, color: color)),
        if (mine) ...[
          const SizedBox(width: 4),
          Icon(
            message.status == MessageStatus.read ? Icons.done_all : Icons.done,
            size: 13,
            color: color,
          ),
        ],
      ],
    );
  }

  String _time(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}
