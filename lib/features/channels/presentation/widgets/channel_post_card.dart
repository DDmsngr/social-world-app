import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/markdown_view.dart';
import '../../data/channels_repository.dart';
import 'channel_media.dart';

/// Пост канала. Текст — Markdown (ссылки из источника открываются после
/// подтверждения), вложение — тот же виджет, что в чатах.
class ChannelPostCard extends StatelessWidget {
  const ChannelPostCard({
    super.key,
    required this.post,
    this.onComments,
    this.onLongPress,
    this.full = false,
  });

  final ChannelPost post;
  final VoidCallback? onComments;
  final VoidCallback? onLongPress;

  /// На экране обсуждения текст не обрезается и кнопка комментариев не нужна.
  final bool full;

  @override
  Widget build(BuildContext context) {
    final message = post.message;
    final text = message.text?.trim() ?? '';

    // Тап по самому посту открывает его с обсуждением: комментарии живут
    // внутри поста, а не в ленте канала.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: full ? null : onComments,
      onLongPress: onLongPress,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.hair),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (message.attachment != null) ChannelMedia(message: message),
            if (text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: full || text.length <= 700
                    ? MarkdownView(data: text, selectable: full)
                    : MarkdownView(data: '${text.substring(0, 700).trimRight()}…'),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 6, 4),
              child: Row(
                children: [
                  Text(
                    _when(message.sentAt),
                    style: TextStyle(fontSize: 12, color: AppColors.textFaint),
                  ),
                  const Spacer(),
                  if (!full)
                    TextButton.icon(
                      onPressed: onComments,
                      icon: const Icon(Icons.mode_comment_outlined, size: 18),
                      label: Text(
                        post.commentCount == 0
                            ? 'Обсудить'
                            : 'Комментарии · ${post.commentCount}',
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _when(DateTime time) {
  final now = DateTime.now();
  final hh = time.hour.toString().padLeft(2, '0');
  final mm = time.minute.toString().padLeft(2, '0');
  if (time.year == now.year && time.month == now.month && time.day == now.day) {
    return '$hh:$mm';
  }
  const months = [
    'янв', 'фев', 'мар', 'апр', 'мая', 'июн',
    'июл', 'авг', 'сен', 'окт', 'ноя', 'дек',
  ];
  return '${time.day} ${months[time.month - 1]}, $hh:$mm';
}
