/// Фирменные стикеры: каталог из `assets/stickers/manifest.json` и поиск по
/// словам.
///
/// Стикер в сообщении — это его [Sticker.id] (`<пак>.<ключ>`) плюс
/// эмодзи-заменитель в тексте. Старые версии приложения видят только эмодзи,
/// новые рисуют картинку из ассетов. Id уходит в сообщения навсегда, поэтому
/// не меняется, даже если стикер перерисуют.
library;

class Sticker {
  const Sticker({
    required this.packId,
    required this.key,
    required this.emoji,
    required this.title,
    this.synonyms = const [],
    this.emotions = const [],
  });

  final String packId;
  final String key;

  /// Заменитель для старых версий, превью в списке чатов и пуша.
  final String emoji;

  /// Основное название — по нему поиск ставит стикер выше всего.
  final String title;
  final List<String> synonyms;

  /// Семейства эмоций (см. [StickerCatalog.families]); первое — главное.
  final List<String> emotions;

  String get id => '$packId.$key';

  String get asset => stickerAsset(id)!;
}

class StickerPack {
  const StickerPack({
    required this.id,
    required this.title,
    required this.stickers,
  });

  final String id;
  final String title;
  final List<Sticker> stickers;
}

final _idPattern = RegExp(r'^([a-z0-9_]{1,32})\.([a-z0-9_]{1,48})$');

/// Путь к картинке стикера по его id. null — id не похож на наш: он пришёл
/// в сообщении, а сообщение мог собрать кто угодно.
String? stickerAsset(String? id) {
  final match = id == null ? null : _idPattern.firstMatch(id);
  if (match == null) return null;
  return 'assets/stickers/${match[1]}/${match[2]}.webp';
}

class StickerCatalog {
  StickerCatalog({required this.packs, required this.families}) {
    for (final pack in packs) {
      for (final sticker in pack.stickers) {
        _byId[sticker.id] = sticker;
        _index.add(
          _Indexed(
            sticker,
            name: _tokens(sticker.title),
            extra: [for (final s in sticker.synonyms) ..._tokens(s)],
            emoji: _bareEmoji(sticker.emoji),
            order: _index.length,
          ),
        );
      }
    }
    for (final entry in families.entries) {
      _familyStems[entry.key] = [for (final w in entry.value) ..._tokens(w)];
    }
  }

  factory StickerCatalog.fromJson(Map<String, dynamic> json) {
    final families = <String, List<String>>{
      for (final entry in (json['families'] as Map? ?? const {}).entries)
        entry.key as String: [for (final w in entry.value as List) w as String],
    };
    final packs = <StickerPack>[
      for (final raw in json['packs'] as List? ?? const [])
        StickerPack(
          id: raw['id'] as String,
          title: raw['title'] as String? ?? '',
          stickers: [
            for (final s in raw['stickers'] as List? ?? const [])
              if (_idPattern.firstMatch(s['id'] as String? ?? '')
                  case final match?)
                Sticker(
                  packId: match[1]!,
                  key: match[2]!,
                  emoji: s['emoji'] as String? ?? '',
                  title: s['title'] as String? ?? '',
                  synonyms: [
                    for (final w in s['synonyms'] as List? ?? const [])
                      w as String,
                  ],
                  emotions: [
                    for (final w in s['emotions'] as List? ?? const [])
                      w as String,
                  ],
                ),
          ],
        ),
    ];
    return StickerCatalog(packs: packs, families: families);
  }

  final List<StickerPack> packs;

  /// Семейство эмоции → слова, которыми его ищут («любовь», «люблю»,
  /// «сердце»…). Любое слово семейства находит все стикеры семейства.
  final Map<String, List<String>> families;

  final _byId = <String, Sticker>{};
  final _index = <_Indexed>[];
  final _familyStems = <String, List<String>>{};

  Sticker? byId(String? id) => id == null ? null : _byId[id];

  /// Стикеры по словам или эмодзи. Порядок: совпало название, потом
  /// синонимы, потом стикеры, где эта эмоция главная, потом побочные.
  /// Запрос из нескольких слов требует совпадения по каждому.
  List<Sticker> search(String query, {int limit = 40}) {
    final emoji = _bareEmoji(query.trim());
    final words = _tokens(query);
    if (words.isEmpty && emoji.isEmpty) return const [];

    final scores = <_Indexed, int>{};
    // Сколько слов запроса совпало: стикер должен подойти под каждое.
    final matched = <_Indexed, int>{};
    if (words.isEmpty) {
      // Одни эмодзи: стикеры с тем же заменителем.
      for (final item in _index) {
        if (item.emoji.isNotEmpty && item.emoji == emoji) scores[item] = 4;
      }
    }
    for (final q in words) {
      final hitFamilies = {
        for (final entry in _familyStems.entries)
          if (_hit(q, entry.value)) entry.key,
      };
      for (final item in _index) {
        final emotions = item.sticker.emotions;
        final score = _hit(q, item.name)
            ? 4
            : _hit(q, item.extra)
            ? 3
            : emotions.isNotEmpty && hitFamilies.contains(emotions.first)
            ? 2
            : emotions.any(hitFamilies.contains)
            ? 1
            : 0;
        if (score > 0) {
          scores[item] = (scores[item] ?? 0) + score;
          matched[item] = (matched[item] ?? 0) + 1;
        }
      }
    }
    final ranked =
        [
          for (final entry in scores.entries)
            if (words.isEmpty || matched[entry.key] == words.length) entry,
        ]..sort((a, b) {
          final byScore = b.value.compareTo(a.value);
          return byScore != 0 ? byScore : a.key.order.compareTo(b.key.order);
        });
    return [for (final entry in ranked.take(limit)) entry.key.sticker];
  }
}

class _Indexed {
  _Indexed(
    this.sticker, {
    required this.name,
    required this.extra,
    required this.emoji,
    required this.order,
  });

  final Sticker sticker;
  final List<String> name;
  final List<String> extra;
  final String emoji;
  final int order;
}

/// Окончания, которые отрезаются, чтобы «любовь», «любви» и «любовью» стали
/// одной основой. Длинные — первыми.
const _endings = [
  'ость',
  'ение',
  'ания',
  'ание',
  'ыми',
  'ими',
  'ого',
  'его',
  'ому',
  'ему',
  'ых',
  'их',
  'ую',
  'юю',
  'ая',
  'яя',
  'ое',
  'ее',
  'ие',
  'ые',
  'ом',
  'ем',
  'ам',
  'ям',
  'ах',
  'ях',
  'ов',
  'ев',
  'ей',
  'ой',
  'ий',
  'ый',
  'ть',
  'ет',
  'ют',
  'ит',
  'ят',
  'ал',
  'ил',
  'ла',
  'ли',
  'ь',
  'ы',
  'и',
  'а',
  'я',
  'у',
  'ю',
  'е',
  'о',
];

String _stem(String word) {
  final w = word.toLowerCase().replaceAll('ё', 'е');
  for (final ending in _endings) {
    if (w.endsWith(ending) && w.length - ending.length >= 3) {
      return w.substring(0, w.length - ending.length);
    }
  }
  return w;
}

final _letters = RegExp(r'[a-zа-яё0-9]+', caseSensitive: false, unicode: true);

/// Предлоги, частицы и местоимения: из «смех до слёз» в поиск идут «смех» и
/// «слёзы», а не «до» — иначе на каждое «да», «ну», «не» в переписке
/// всплывала бы полоса стикеров.
const _stopWords = {
  'а',
  'и',
  'в',
  'с',
  'к',
  'у',
  'о',
  'я',
  'да',
  'до',
  'же',
  'за',
  'на',
  'не',
  'ни',
  'ну',
  'от',
  'по',
  'со',
  'из',
  'бы',
  'ли',
  'то',
  'ты',
  'мы',
  'вы',
  'он',
  'она',
  'оно',
  'они',
  'так',
  'как',
  'что',
  'это',
};

List<String> _tokens(String text) => [
  for (final match in _letters.allMatches(text))
    if (!_stopWords.contains(match[0]!.toLowerCase())) _stem(match[0]!),
];

/// Основа слова запроса [q] совпадает с одним из слов стикера по началу:
/// «люб» находит «любовь», «влюблён» — нет (это отдельное слово семейства).
/// Слова короче трёх букв — только целиком: иначе «да» и «ну» в каждом
/// сообщении тянули бы полосу стикеров.
bool _hit(String q, List<String> words) {
  if (q.length < 2) return false;
  if (q.length < 3) return words.contains(q);
  for (final w in words) {
    if (w.startsWith(q) || (w.length >= 3 && q.startsWith(w))) return true;
  }
  return false;
}

/// Эмодзи без вариантных селекторов: «❤️» и «❤» — одно и то же. Буквы и
/// цифры отбрасываются, так что для обычного слова получится пустая строка.
String _bareEmoji(String text) {
  final buffer = StringBuffer();
  for (final rune in text.runes) {
    if (rune == 0xFE0F || rune == 0xFE0E || rune < 0x2000) continue;
    buffer.writeCharCode(rune);
  }
  return buffer.toString();
}
