/// Короткий плоский текст из Markdown — для карточки статьи в ленте, где
/// целиком рендерить длинный материал незачем.
String markdownPreview(String source, {int maxChars = 220}) {
  var text = source;

  text = text.replaceAll(RegExp(r'```[\s\S]*?```'), ' ');
  // Картинки уходят целиком, у ссылок остаётся подпись.
  text = text.replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), ' ');
  text = text.replaceAllMapped(RegExp(r'\[([^\]]*)\]\([^)]*\)'), (m) => m[1]!);
  text = text.replaceAll(RegExp(r'^\s{0,3}#{1,6}\s*', multiLine: true), '');
  text = text.replaceAll(RegExp(r'^\s{0,3}>\s?', multiLine: true), '');
  text = text.replaceAll(RegExp(r'^\s*[-*+]\s+', multiLine: true), '');
  text = text.replaceAll(RegExp(r'^\s*\d+\.\s+', multiLine: true), '');
  text = text.replaceAll(RegExp(r'[*_`~]+'), '');
  text = text.replaceAll(RegExp(r'\s+'), ' ').trim();

  if (text.length <= maxChars) return text;
  final cut = text.substring(0, maxChars);
  final space = cut.lastIndexOf(' ');
  return '${(space > maxChars * 0.6 ? cut.substring(0, space) : cut).trimRight()}…';
}
