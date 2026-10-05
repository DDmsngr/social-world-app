import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../router/app_router.dart';
import '../text/hashtags.dart';
import '../theme/app_colors.dart';

/// Обычный текст, в котором хэштеги — ссылки на ленту тега.
class HashtagText extends StatefulWidget {
  const HashtagText(this.text, {super.key, this.style, this.maxLines});

  final String text;
  final TextStyle? style;
  final int? maxLines;

  @override
  State<HashtagText> createState() => _HashtagTextState();
}

class _HashtagTextState extends State<HashtagText> {
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

  @override
  Widget build(BuildContext context) {
    _clear();
    final spans = <InlineSpan>[];
    var from = 0;
    for (final m in hashtagPattern.allMatches(widget.text)) {
      if (m.start > from) spans.add(TextSpan(text: widget.text.substring(from, m.start)));
      final tag = m.group(1)!.toLowerCase();
      final recognizer = TapGestureRecognizer()
        ..onTap = () => context.push('${Routes.hashtag}/${Uri.encodeComponent(tag)}');
      _recognizers.add(recognizer);
      spans.add(
        TextSpan(
          text: m.group(0),
          style: TextStyle(color: AppColors.primaryTint),
          recognizer: recognizer,
        ),
      );
      from = m.end;
    }
    if (from < widget.text.length) spans.add(TextSpan(text: widget.text.substring(from)));

    return Text.rich(
      TextSpan(style: widget.style, children: spans),
      maxLines: widget.maxLines,
      overflow: widget.maxLines == null ? null : TextOverflow.ellipsis,
    );
  }
}
