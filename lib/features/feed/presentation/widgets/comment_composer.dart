import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/entities/comment.dart';

/// Поле ответа под обсуждением: постов ленты и постов каналов.
class CommentComposer extends StatelessWidget {
  const CommentComposer({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.replyTo,
    required this.sending,
    required this.onCancelReply,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final Comment? replyTo;
  final bool sending;
  final VoidCallback onCancelReply;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.ink2,
          border: Border(top: BorderSide(color: AppColors.hair)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 8, 12, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (replyTo != null)
                Row(
                  children: [
                    Icon(Icons.reply, size: 14, color: AppColors.primaryTint),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Ответ: ${replyTo!.authorName}',
                        style: AppTypography.serif(13, color: AppColors.primaryTint),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      onPressed: onCancelReply,
                      tooltip: 'Отменить ответ',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close, size: 16),
                    ),
                  ],
                ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      maxLines: 4,
                      minLines: 1,
                      maxLength: 2000,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Написать комментарий',
                        counterText: '',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: sending ? null : onSend,
                    tooltip: 'Отправить',
                    icon: sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(Icons.send, color: AppColors.primaryTint),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
