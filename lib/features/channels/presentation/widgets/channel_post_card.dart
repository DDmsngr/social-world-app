import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/markdown_view.dart';
import '../../../chat/presentation/providers/chat_extras_providers.dart';
import '../../../chat/presentation/widgets/reaction_chips.dart';
import '../../../create/domain/article_parts.dart';
import '../../data/channels_repository.dart';
import 'channel_media.dart';

/// Пост канала. Текст — Markdown (ссылки из источника открываются после
/// подтверждения), вложение — тот же виджет, что в чатах.
class ChannelPostCard extends StatelessWidget {
  const ChannelPostCard({
    super.key,
    required this.post,
    this.onComments,
    this.onTap,
    this.onLongPress,
    this.reactions = const [],
    this.onReact,
    this.full = false,
  });

  final ChannelPost post;
  final VoidCallback? onComments;

  /// Короткий тап по посту. Контекст карточки нужен, чтобы повесить панель
  /// реакций у самого поста. Без него тап ведёт в обсуждение.
  final void Function(BuildContext context)? onTap;
  final void Function(BuildContext context)? onLongPress;
  final List<ReactionCount> reactions;
  final void Function(String emoji)? onReact;

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
      onTap: full
          ? null
          : onTap != null
          ? () => onTap!(context)
          : onComments,
      onLongPress: onLongPress == null ? null : () => onLongPress!(context),
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
                    : MarkdownView(data: channelPostPreview(text)),
              ),
            if (reactions.isNotEmpty && onReact != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                child: ReactionChips(reactions: reactions, mine: false, onTap: onReact!),
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

/// Начало длинного поста для ленты канала. Статью режем по блокам, а не по
/// символам: обрезка посреди `![фото](ссылка)` оставила бы в ленте обломок
/// разметки. Показываем текст до ~600 знаков и первое фото/видео.
String channelPostPreview(String text) {
  final parts = parseArticle(text);
  final out = <String>[];
  var length = 0;
  var media = false;
  for (final part in parts) {
    switch (part) {
      case TextPart(text: final t):
        if (t.trim().isEmpty) continue;
        if (length >= 600) break;
        final room = 600 - length;
        final piece = t.length <= room ? t : '${t.substring(0, room).trimRight()}…';
        out.add(piece);
        length += piece.length;
      case MediaPart(:final url, :final alt):
        if (media) continue;
        media = true;
        out.add('![$alt]($url)');
    }
  }
  final preview = out.join('\n\n');
  return preview.length < text.length && !preview.endsWith('…') ? '$preview\n\n…' : preview;
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
