import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../links/deep_links.dart';
import '../router/app_router.dart';
import '../text/hashtags.dart';
import '../theme/app_colors.dart';
import 'markdown_view.dart' show isSafeLink;

final _urlPattern = RegExp(r'https?://[^\s<>"]+', caseSensitive: false);

/// Знаки, которыми предложение заканчивается после ссылки, но к ней не относятся.
const _trailing = '.,;:!?)]}»…';

/// Текст, в котором ссылки нажимаются: ссылка на объект ChaWo (пост, место,
/// квест…) открывается внутри приложения, остальные — в браузере после
/// подтверждения. [hashtags] — ещё и `#теги` ведут на ленту тега.
class LinkText extends StatefulWidget {
  const LinkText(
    this.text, {
    super.key,
    this.style,
    this.linkColor,
    this.hashtags = false,
    this.selectable = false,
    this.maxLines,
  });

  final String text;
  final TextStyle? style;
  final Color? linkColor;
  final bool hashtags;
  final bool selectable;
  final int? maxLines;

  @override
  State<LinkText> createState() => _LinkTextState();
}

class _LinkTextState extends State<LinkText> {
  final _recognizers = <TapGestureRecognizer>[];

  void _clear() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _clear();
    super.dispose();
  }

  Future<void> _open(String raw) async {
    final uri = Uri.tryParse(raw);
    if (uri == null) return;

    // Ссылка на объект ChaWo — открываем у себя, без браузера.
    final inApp = DeepLinks.parse(uri);
    if (inApp != null) {
      context.push(inApp.location);
      return;
    }
    if (!isSafeLink(raw)) return;

    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Открыть ссылку?'),
        content: Text(uri.toString(), style: const TextStyle(fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Открыть'),
          ),
        ],
      ),
    );
    if (go == true) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// Куски текста: обычные и нажимаемые (ссылка или тег).
  List<({int start, int end, VoidCallback onTap})> _links() {
    final found = <({int start, int end, VoidCallback onTap})>[];
    for (final m in _urlPattern.allMatches(widget.text)) {
      var end = m.end;
      while (end > m.start + 1 && _trailing.contains(widget.text[end - 1])) {
        end--;
      }
      final url = widget.text.substring(m.start, end);
      found.add((start: m.start, end: end, onTap: () => _open(url)));
    }
    if (widget.hashtags) {
      for (final m in hashtagPattern.allMatches(widget.text)) {
        // Решётка внутри ссылки (`…/page#top`) — часть ссылки.
        if (found.any((f) => m.start >= f.start && m.start < f.end)) continue;
        final tag = m.group(1)!.toLowerCase();
        found.add((
          start: m.start,
          end: m.end,
          onTap: () => context.push('${Routes.hashtag}/${Uri.encodeComponent(tag)}'),
        ));
      }
      found.sort((a, b) => a.start.compareTo(b.start));
    }
    return found;
  }

  @override
  Widget build(BuildContext context) {
    _clear();
    final color = widget.linkColor ?? AppColors.primaryTint;
    final spans = <InlineSpan>[];
    var from = 0;
    for (final link in _links()) {
      if (link.start > from) {
        spans.add(TextSpan(text: widget.text.substring(from, link.start)));
      }
      final recognizer = TapGestureRecognizer()..onTap = link.onTap;
      _recognizers.add(recognizer);
      spans.add(
        TextSpan(
          text: widget.text.substring(link.start, link.end),
          style: TextStyle(color: color, decoration: TextDecoration.underline, decorationColor: color),
          recognizer: recognizer,
        ),
      );
      from = link.end;
    }
    if (from < widget.text.length) spans.add(TextSpan(text: widget.text.substring(from)));

    final span = TextSpan(style: widget.style, children: spans);
    return widget.selectable
        ? SelectableText.rich(span, maxLines: widget.maxLines)
        : Text.rich(
            span,
            maxLines: widget.maxLines,
            overflow: widget.maxLines == null ? null : TextOverflow.ellipsis,
          );
  }
}
