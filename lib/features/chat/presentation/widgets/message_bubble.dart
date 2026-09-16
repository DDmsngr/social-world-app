import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/chat_message.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({super.key, required this.message, required this.mine});

  final ChatMessage message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final radius = Radius.circular(AppRadius.card);

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        decoration: BoxDecoration(
          color: mine ? AppColors.primary : AppColors.card,
          border: mine ? null : Border.all(color: AppColors.hair),
          borderRadius: BorderRadius.only(
            topLeft: radius,
            topRight: radius,
            bottomLeft: mine ? radius : const Radius.circular(4),
            bottomRight: mine ? const Radius.circular(4) : radius,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              message.text ?? '',
              style: TextStyle(
                fontSize: 15,
                height: 1.4,
                color: mine ? AppColors.onPrimary : AppColors.text,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Подделанную подпись нельзя показывать как обычное сообщение.
                if (message.signatureValid == false) ...[
                  const Icon(
                    Icons.gpp_maybe_outlined,
                    size: 13,
                    color: AppColors.danger,
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'подпись не сходится',
                    style: TextStyle(fontSize: 11, color: AppColors.danger),
                  ),
                  const SizedBox(width: 8),
                ],
                Text(
                  _time(message.sentAt),
                  style: TextStyle(
                    fontSize: 11,
                    color: mine
                        ? AppColors.onPrimary.withValues(alpha: 0.7)
                        : AppColors.textFaint,
                  ),
                ),
                if (mine) ...[
                  const SizedBox(width: 4),
                  Icon(
                    message.status == MessageStatus.read
                        ? Icons.done_all
                        : Icons.done,
                    size: 13,
                    color: AppColors.onPrimary.withValues(alpha: 0.7),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _time(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}
