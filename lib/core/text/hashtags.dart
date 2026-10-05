/// Хэштег: «#», затем 2–50 букв любого алфавита, цифр или «_». То же правило,
/// что у сервера (`extract_hashtags` в миграции 0048).
final hashtagPattern = RegExp(r'#([\p{L}\p{N}_]{2,50})', unicode: true);

/// Теги из текста без «#», в нижнем регистре, без повторов, по порядку.
List<String> extractHashtags(String? text) {
  if (text == null || text.isEmpty) return const [];
  final seen = <String>{};
  return [
    for (final m in hashtagPattern.allMatches(text))
      if (seen.add(m.group(1)!.toLowerCase())) m.group(1)!.toLowerCase(),
  ];
}

/// Тег из того, что ввёл человек или пришло в ссылке: без «#» и пробелов.
String normalizeHashtag(String raw) => raw.trim().replaceFirst(RegExp(r'^#+'), '').toLowerCase();
