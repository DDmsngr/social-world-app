import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../chat/presentation/widgets/emoji_panel.dart';
import '../../domain/entities/comment.dart';

/// Поле ответа под обсуждением: постов ленты и постов каналов. Кнопка со
/// смайликом открывает ту же панель эмодзи, что в чатах, на месте клавиатуры;
/// комментарий из 1–3 эмодзи показывается крупно, как стикер.
class CommentComposer extends StatefulWidget {
  const CommentComposer({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.replyTo,
    required this.sending,
    required this.onCancelReply,
    required this.onSend,
    this.attachments = const [],
    this.onPickPhotos,
    this.onPickGif,
    this.onRemoveAttachment,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final Comment? replyTo;
  final bool sending;
  final VoidCallback onCancelReply;
  final VoidCallback onSend;

  /// Выбранные, но ещё не отправленные картинки (пути на телефоне).
  final List<String> attachments;

  /// Пока null, кнопки вложения нет (например, в комментариях к постам
  /// каналов).
  final VoidCallback? onPickPhotos;
  final VoidCallback? onPickGif;
  final void Function(int index)? onRemoveAttachment;

  @override
  State<CommentComposer> createState() => _CommentComposerState();
}

class _CommentComposerState extends State<CommentComposer> {
  var _emoji = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocus);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocus);
    super.dispose();
  }

  // Клавиатура открылась (тап по полю) — панель эмодзи уходит.
  void _onFocus() {
    if (widget.focusNode.hasFocus && _emoji) setState(() => _emoji = false);
  }

  void _toggleEmoji() {
    if (_emoji) {
      setState(() => _emoji = false);
      widget.focusNode.requestFocus();
    } else {
      widget.focusNode.unfocus();
      SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      setState(() => _emoji = true);
    }
  }

  void _insert(String emoji) => widget.controller.value = insertAtSelection(widget.controller.value, emoji);

  @override
  Widget build(BuildContext context) {
    final replyTo = widget.replyTo;
    return SafeArea(
      top: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.ink2,
          border: Border(top: BorderSide(color: AppColors.hair)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (replyTo != null)
                    Padding(
                      padding: const EdgeInsets.only(left: AppSpacing.gutter - 4),
                      child: Row(
                        children: [
                          Icon(Icons.reply, size: 14, color: AppColors.primaryTint),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Ответ: ${replyTo.authorName}',
                              style: AppTypography.serif(13, color: AppColors.primaryTint),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            onPressed: widget.onCancelReply,
                            tooltip: 'Отменить ответ',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.close, size: 16),
                          ),
                        ],
                      ),
                    ),
                  if (widget.attachments.isNotEmpty)
                    SizedBox(
                      height: 64,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.fromLTRB(AppSpacing.gutter - 4, 0, 0, 8),
                        itemCount: widget.attachments.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (context, index) => Stack(
                          clipBehavior: Clip.none,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(
                                File(widget.attachments[index]),
                                width: 56,
                                height: 56,
                                fit: BoxFit.cover,
                                cacheWidth: 160,
                              ),
                            ),
                            Positioned(
                              top: -6,
                              right: -6,
                              child: GestureDetector(
                                onTap: () => widget.onRemoveAttachment?.call(index),
                                child: CircleAvatar(
                                  radius: 10,
                                  backgroundColor: AppColors.ink,
                                  child: Icon(Icons.close, size: 13, color: AppColors.text),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Row(
                    children: [
                      if (widget.onPickPhotos != null)
                        PopupMenuButton<String>(
                          tooltip: 'Фото или GIF',
                          icon: Icon(Icons.add_photo_alternate_outlined, color: AppColors.textDim),
                          onSelected: (value) =>
                              value == 'gif' ? widget.onPickGif?.call() : widget.onPickPhotos?.call(),
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'photo', child: Text('Фото из галереи')),
                            PopupMenuItem(value: 'gif', child: Text('GIF-файл')),
                          ],
                        ),
                      IconButton(
                        onPressed: _toggleEmoji,
                        tooltip: _emoji ? 'Клавиатура' : 'Эмодзи и стикеры',
                        icon: Icon(
                          _emoji ? Icons.keyboard_outlined : Icons.emoji_emotions_outlined,
                          color: AppColors.textDim,
                        ),
                      ),
                      Expanded(
                        child: TextField(
                          controller: widget.controller,
                          focusNode: widget.focusNode,
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
                        onPressed: widget.sending ? null : widget.onSend,
                        tooltip: 'Отправить',
                        icon: widget.sending
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
            if (_emoji)
              EmojiPanel(
                onPick: _insert,
                onBackspace: () => widget.controller.value = deleteBeforeSelection(widget.controller.value),
              ),
          ],
        ),
      ),
    );
  }
}
