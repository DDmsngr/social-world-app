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
class ChannelPostCard extends StatefulWidget {
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
  State<ChannelPostCard> createState() => _ChannelPostCardState();
}

class _ChannelPostCardState extends State<ChannelPostCard> {
  /// Длинный пост в ленте идёт с обрезкой; тап по нему разворачивает на месте.
  bool _expanded = false;

  final _moreKey = GlobalKey();

  double? _y(BuildContext? target) {
    final box = target?.findRenderObject();
    return box is RenderBox && box.attached ? box.localToGlobal(Offset.zero).dy : null;
  }

  /// Разворот и сворачивание не должны сдвигать то, что читают: лента канала
  /// растёт вверх от нижнего края, и «Читать дальше» уносило текст за экран.
  /// Разворот держит на месте верх карточки — продолжение текста идёт ровно с
  /// обрыва. Сворачивание держит саму кнопку: верх длинного поста обычно уже
  /// за экраном, и человек остаётся там, где нажал.
  void _toggle() {
    final expanding = !_expanded;
    final anchor = expanding ? () => _y(context) : () => _y(_moreKey.currentContext);
    final before = anchor();
    setState(() => _expanded = !_expanded);
    if (before == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final after = anchor();
      final scrollable = Scrollable.maybeOf(context);
      if (after == null || scrollable == null) return;
      final shift = before - after; // на сколько карточку надо опустить
      if (shift.abs() < 1) return;
      final position = scrollable.position;
      final reversed = scrollable.axisDirection == AxisDirection.up;
      final target = position.pixels + (reversed ? shift : -shift);
      position.jumpTo(target.clamp(position.minScrollExtent, position.maxScrollExtent));
    });
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final onComments = widget.onComments;
    final onTap = widget.onTap;
    final onLongPress = widget.onLongPress;
    final reactions = widget.reactions;
    final onReact = widget.onReact;
    final full = widget.full;
    final message = post.message;
    final text = message.text?.trim() ?? '';
    final collapsed = !full && !_expanded && text.length > 700;

    // Обрезанный пост тап разворачивает; развёрнутый и короткий открывает
    // реакции (или обсуждение, если обработчика нет).
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: full
          ? null
          : collapsed
          ? _toggle
          : onTap != null
          ? () => onTap(context)
          : onComments,
      onLongPress: onLongPress == null ? null : () => onLongPress(context),
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
                child: collapsed
                    ? MarkdownView(data: channelPostPreview(text))
                    : MarkdownView(data: text, selectable: full),
              ),
            if (!full && text.length > 700)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: GestureDetector(
                  key: _moreKey,
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggle,
                  child: Text(
                    _expanded ? 'Свернуть' : 'Читать дальше',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
            if (reactions.isNotEmpty && onReact != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                child: ReactionChips(reactions: reactions, mine: false, onTap: onReact),
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
