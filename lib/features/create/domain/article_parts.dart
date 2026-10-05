/// Статья как последовательность блоков: текст, фото или видео, снова текст.
/// В базе она по-прежнему лежит одной строкой Markdown (`![фото](ссылка)`
/// отдельным абзацем), поэтому лента и чтение ничего не знают про блоки.
sealed class ArticlePart {
  const ArticlePart();
}

class TextPart extends ArticlePart {
  const TextPart(this.text);

  final String text;
}

class MediaPart extends ArticlePart {
  const MediaPart(this.url, [this.alt = 'фото']);

  final String url;
  final String alt;
}

final _token = RegExp(r'!\[([^\]]*)\]\(([^)\s]+)\)');

String _trimBreaks(String value) =>
    value.replaceAll(RegExp(r'^\n+|\n+$'), '');

/// Разбирает Markdown на блоки. Фото и видео, стоящие посреди абзаца,
/// выносятся в отдельный блок.
List<ArticlePart> parseArticle(String markdown) {
  final parts = <ArticlePart>[];
  var from = 0;
  for (final match in _token.allMatches(markdown)) {
    parts.add(TextPart(_trimBreaks(markdown.substring(from, match.start))));
    parts.add(MediaPart(match.group(2)!, match.group(1) ?? 'фото'));
    from = match.end;
  }
  parts.add(TextPart(_trimBreaks(markdown.substring(from))));
  return normalizeParts(parts);
}

/// Склеивает соседние тексты и следит, чтобы текстовый блок стоял в начале,
/// в конце и между любыми двумя медиа: именно туда человек ставит курсор.
List<ArticlePart> normalizeParts(List<ArticlePart> parts) {
  final out = <ArticlePart>[];
  for (final part in parts) {
    final last = out.isEmpty ? null : out.last;
    if (part is TextPart && last is TextPart) {
      final joined = [last.text, part.text].where((t) => t.isNotEmpty).join('\n\n');
      out[out.length - 1] = TextPart(joined);
    } else if (part is MediaPart && (last == null || last is MediaPart)) {
      out
        ..add(const TextPart(''))
        ..add(part);
    } else {
      out.add(part);
    }
  }
  if (out.isEmpty || out.last is MediaPart) out.add(const TextPart(''));
  return out;
}

/// Собирает Markdown обратно: пустые тексты пропускаются, блоки — через пустую
/// строку.
String serializeArticle(List<ArticlePart> parts) {
  final chunks = <String>[];
  for (final part in parts) {
    switch (part) {
      case TextPart(:final text):
        final clean = _trimBreaks(text);
        if (clean.trim().isNotEmpty) chunks.add(clean);
      case MediaPart(:final url, :final alt):
        chunks.add('![$alt]($url)');
    }
  }
  return chunks.join('\n\n');
}
