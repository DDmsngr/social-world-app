import 'dart:convert';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/link_text.dart';
import '../../../../core/widgets/video_poster.dart';
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
    this.reactions,
    this.highlighted = false,
  });

  /// Подсветка при переходе к сообщению и при выделении для меню.
  final bool highlighted;

  /// Плашки реакций живут внутри пузыря, над временем.
  final Widget? reactions;

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
            widthFactor: 1,
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
          Align(
            alignment: Alignment.centerLeft,
            widthFactor: 1,
            child: SizedBox(
              width: 260,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: MessageAlbum(message: message),
              ),
            ),
          )
        else if (hasAttachment)
          // Медиа и подпись под ним — по одному левому краю: раньше фото
          // уезжало вправо, а текст оставался слева, и пузырь выглядел кривым.
          Align(
            alignment: Alignment.centerLeft,
            widthFactor: 1,
            child: AttachmentView(message: message, mine: mine, onMore: onMediaMore),
          ),
        if (!bare && (!hasAttachment || caption.isNotEmpty)) ...[
          if (hasAttachment) const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            widthFactor: 1,
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
        if (message.linkPreview != null && !bare)
          _LinkPreviewCard(preview: message.linkPreview!, mine: mine),
        if (reactions != null)
          Align(alignment: Alignment.centerLeft, widthFactor: 1, child: reactions),
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
                color: highlighted
                    ? Color.alphaBlend(
                        AppColors.primary.withValues(alpha: 0.38),
                        mine ? AppColors.bubbleMine : AppColors.card,
                      )
                    : (mine ? AppColors.bubbleMine : AppColors.card),
                border: highlighted
                    ? Border.all(color: AppColors.primaryTint)
                    : (mine ? null : Border.all(color: AppColors.hair)),
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
            widthFactor: 1,
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
/// Карточка ссылки под текстом: заголовок, описание, маленькая картинка.
class _LinkPreviewCard extends StatelessWidget {
  const _LinkPreviewCard({required this.preview, required this.mine});

  final LinkPreview preview;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final dim = mine ? AppColors.onBubbleMine.withValues(alpha: 0.75) : AppColors.textDim;
    final image = preview.imageB64;
    Uint8List? bytes;
    if (image != null) {
      try {
        bytes = base64Decode(image);
      } catch (_) {
        bytes = null;
      }
    }
    return Semantics(
      button: true,
      label: 'Открыть ссылку: ${preview.title ?? preview.url}',
      child: GestureDetector(
        onTap: () {
          final uri = Uri.tryParse(preview.url);
          if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
        },
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
          decoration: BoxDecoration(
            color: AppColors.ink.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(10),
            border: Border(left: BorderSide(color: AppColors.primaryTint, width: 3)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      Uri.tryParse(preview.url)?.host.replaceFirst('www.', '') ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: dim),
                    ),
                    if (preview.title != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          preview.title!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: mine ? AppColors.onBubbleMine : AppColors.text,
                          ),
                        ),
                      ),
                    if (preview.description != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          preview.description!,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12.5, height: 1.3, color: dim),
                        ),
                      ),
                  ],
                ),
              ),
              if (bytes != null)
                Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(bytes, width: 56, height: 56, fit: BoxFit.cover, gaplessPlayback: true),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuoteBlock extends StatelessWidget {
  const _QuoteBlock({required this.reply, required this.mine});

  final ChatReply reply;
  final bool mine;

  /// Превью оригинала: зашитое в цитату, иначе по ссылке (фото истории или
  /// кадр видео). Для видео поверх — значок «играть».
  Widget? _thumb() {
    final isVideo = reply.kind == MessageKind.video || reply.kind == MessageKind.videoNote;
    Widget? image;
    final b64 = reply.thumbB64;
    if (b64 != null) {
      try {
        image = Image.memory(base64Decode(b64), fit: BoxFit.cover, gaplessPlayback: true);
      } catch (_) {
        image = null;
      }
    }
    final url = reply.thumbUrl;
    if (image == null && url != null) {
      image = isVideo
          ? VideoPoster(url: url, showPlay: false, maxWidth: 160)
          : Image(
              image: CachedNetworkImageProvider(url),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            );
    }
    if (image == null) return null;
    if (!isVideo) return image;
    return Stack(
      fit: StackFit.expand,
      children: [
        image,
        const Center(child: Icon(Icons.play_circle_fill, color: Colors.white70, size: 22)),
      ],
    );
  }

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
      child: Row(
        children: [
          if (_thumb() case final thumb?)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(width: 44, height: 56, child: thumb),
              ),
            ),
          Expanded(
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
          ),
        ],
      ),
    );
  }
}
