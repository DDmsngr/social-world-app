/// Стикеры: каталог магазина (приходит с сервера, см. миграцию 0078) и поиск
/// по словам.
///
/// Стикер в сообщении — это его [Sticker.id] (`<пак>.<ключ>`) плюс
/// эмодзи-заменитель в тексте. Версии без стикеров видят только эмодзи,
/// новые рисуют картинку из публичного бакета `stickers`. Id уходит в
/// сообщения навсегда, поэтому не меняется, даже если стикер перерисуют, а
/// сам стикер с сервера не удаляется (пак только снимают с публикации).
library;

import 'package:flutter/foundation.dart';

import '../../../core/config/env.dart';

class Sticker {
  const Sticker({
    required this.packId,
    required this.key,
    required this.emoji,
    required this.title,
    this.synonyms = const [],
    this.emotions = const [],
    this.image,
    this.thumb,
  });

  final String packId;
  final String key;

  /// Заменитель для старых версий, превью в списке чатов и пуша.
  final String emoji;

  /// Основное название — по нему поиск ставит стикер выше всего. Оно же —
  /// альтернативный текст картинки.
  final String title;
  final List<String> synonyms;

  /// Семейства эмоций (см. [StickerCatalog.families]); первое — главное.
  final List<String> emotions;

  /// Пути в бакете: оригинал (в переписке) и превью (сетки магазина и
  /// панели). null — путь по умолчанию из id.
  final String? image;
  final String? thumb;

  String get id => '$packId.$key';

  /// Картинка для переписки — оригинал.
  String get imageUrl => StickerUrls.file(image ?? '$packId/$key.webp');

  /// Картинка для сеток — превью. Без превью — оригинал.
  String get thumbUrl => thumb == null ? imageUrl : StickerUrls.file(thumb!);
}

/// Статус пака в каталоге (колонка status). Черновики и паки на модерации
/// до приложения не доходят.
enum StickerPackStatus {
  published,

  /// Снят с публикации: в магазине его нет, поставить нельзя, но его
  /// стикеры по-прежнему показываются в старых сообщениях.
  archived;

  static StickerPackStatus parse(Object? value) =>
      value == 'archived' ? archived : published;
}

class StickerPack {
  const StickerPack({
    required this.id,
    required this.title,
    required this.stickers,
    this.description,
    this.publisher = 'Команда ChaWo',
    this.category,
    this.cover,
    this.status = StickerPackStatus.published,
  });

  final String id;
  final String title;
  final List<Sticker> stickers;
  final String? description;
  final String publisher;
  final String? category;

  /// Путь обложки в бакете; null — превью первого стикера.
  final String? cover;
  final StickerPackStatus status;

  bool get isPublished => status == StickerPackStatus.published;

  String? get coverUrl => cover != null
      ? StickerUrls.file(cover!)
      : stickers.isEmpty
      ? null
      : stickers.first.thumbUrl;
}

/// Адреса картинок стикеров: публичный бакет `stickers` на нашем сервере.
abstract final class StickerUrls {
  static String? _base;

  static String get base =>
      _base ?? '${Env.supabaseUrl}/storage/v1/object/public/stickers';

  /// В тестах `.env` нет: адрес задаётся явно.
  @visibleForTesting
  static set baseForTest(String? value) => _base = value;

  static String file(String path) => '$base/$path';
}

final _idPattern = RegExp(r'^([a-z0-9_]{1,32})\.([a-z0-9_]{1,48})$');

/// Похоже ли на id нашего стикера. Id приходит в сообщении, а сообщение мог
/// собрать кто угодно — в адрес картинки попадает только проверенный.
bool isStickerId(String? id) => id != null && _idPattern.hasMatch(id);

/// Пак и ключ из id; null — id не наш.
({String pack, String key})? parseStickerId(String? id) {
  final match = id == null ? null : _idPattern.firstMatch(id);
  return match == null ? null : (pack: match[1]!, key: match[2]!);
}

/// Адрес картинки стикера из сообщения. Пак мог быть не установлен у
/// получателя или вообще снят с публикации — картинка всё равно лежит по
/// этому адресу, каталог для показа не нужен. [thumb] — превью 192 px (для
/// своих эмодзи внутри текста оригинал 512 px не нужен).
String? stickerImageUrl(String? id, {bool thumb = false}) {
  final parts = parseStickerId(id);
  if (parts == null) return null;
  return StickerUrls.file(
    thumb ? '${parts.pack}/thumb/${parts.key}.webp' : '${parts.pack}/${parts.key}.webp',
  );
}

/// Свой эмодзи внутри текста: в [offset] текста стоит [text] — обычный
/// эмодзи-заменитель (его видят старые версии, превью и пуш), а новые
/// версии рисуют на этом месте стикер [sticker] размером с букву.
class CustomEmoji {
  const CustomEmoji({
    required this.offset,
    required this.text,
    required this.sticker,
  });

  /// Смещение в тексте в единицах UTF-16 — как у [String.substring].
  final int offset;
  final String text;
  final String sticker;

  int get end => offset + text.length;

  Map<String, Object?> toJson() => {'o': offset, 't': text, 's': sticker};

  static CustomEmoji? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final offset = raw['o'];
    final text = raw['t'];
    final sticker = raw['s'];
    if (offset is! int || offset < 0) return null;
    if (text is! String || text.isEmpty || text.length > 16) return null;
    if (sticker is! String || !isStickerId(sticker)) return null;
    return CustomEmoji(offset: offset, text: text, sticker: sticker);
  }

  @override
  bool operator ==(Object other) =>
      other is CustomEmoji &&
      other.offset == offset &&
      other.text == text &&
      other.sticker == sticker;

  @override
  int get hashCode => Object.hash(offset, text, sticker);
}

/// Только те свои эмодзи, что действительно стоят в [text] на своём месте:
/// по порядку и без наложений. Текст могли поправить (в группе правка
/// меняет только текст, служебная часть остаётся прежней) — тогда
/// съехавшие отметки просто не рисуются, и видно обычный эмодзи.
List<CustomEmoji> validCustomEmoji(String text, List<CustomEmoji> emoji) {
  final sorted = [...emoji]..sort((a, b) => a.offset.compareTo(b.offset));
  final result = <CustomEmoji>[];
  var from = 0;
  for (final e in sorted) {
    if (e.offset < from || e.end > text.length) continue;
    if (text.substring(e.offset, e.end) != e.text) continue;
    result.add(e);
    from = e.end;
  }
  return result;
}

/// Первый символ области частного использования: свой эмодзи в поле ввода
/// — один такой символ, поэтому курсор и «стереть» работают с ним как с
/// буквой. В сообщение он не уходит: при отправке его заменяет эмодзи.
const inlineEmojiBase = 0xE000;

class StickerCatalog {
  static final empty = StickerCatalog(packs: const [], families: const {});

  StickerCatalog({required this.packs, required this.families}) {
    for (final pack in packs) {
      for (final sticker in pack.stickers) {
        _byId[sticker.id] = sticker;
        _inline[sticker.id] = _index.length;
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
    String? text(Object? value) => value is String && value.isNotEmpty ? value : null;
    final packs = <StickerPack>[
      for (final raw in json['packs'] as List? ?? const [])
        if (raw is Map && raw['id'] is String)
          StickerPack(
            id: raw['id'] as String,
            title: raw['title'] as String? ?? '',
            description: text(raw['description']),
            publisher: text(raw['publisher']) ?? 'Команда ChaWo',
            category: text(raw['category']),
            cover: text(raw['cover']),
            status: StickerPackStatus.parse(raw['status']),
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
                    image: text(s['image']),
                    thumb: text(s['thumb']),
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
  final _inline = <String, int>{};
  final _familyStems = <String, List<String>>{};

  Sticker? byId(String? id) => id == null ? null : _byId[id];

  StickerPack? pack(String? id) {
    for (final pack in packs) {
      if (pack.id == id) return pack;
    }
    return null;
  }

  /// Категории опубликованных паков — для фильтра магазина.
  List<String> get categories => [
    ...{
      for (final pack in packs)
        if (pack.isPublished && pack.category != null) pack.category!,
    },
  ];

  /// Символ, которым свой эмодзи стоит в поле ввода (см. [inlineEmojiBase]).
  String inlineChar(Sticker sticker) =>
      String.fromCharCode(inlineEmojiBase + _inline[sticker.id]!);

  /// Чей это символ в поле ввода; null — обычный символ.
  Sticker? byInlineCode(int codeUnit) {
    final i = codeUnit - inlineEmojiBase;
    return i >= 0 && i < _index.length ? _index[i].sticker : null;
  }

  /// Черновик из поля ввода — в текст для отправки: каждый свой эмодзи
  /// становится обычным эмодзи-заменителем, а его место и id уходят
  /// отдельным списком.
  ({String text, List<CustomEmoji> emoji}) encodeDraft(String draft) {
    final buffer = StringBuffer();
    final emoji = <CustomEmoji>[];
    for (final unit in draft.codeUnits) {
      final sticker = byInlineCode(unit);
      if (sticker == null) {
        buffer.writeCharCode(unit);
        continue;
      }
      emoji.add(
        CustomEmoji(
          offset: buffer.length,
          text: sticker.emoji,
          sticker: sticker.id,
        ),
      );
      buffer.write(sticker.emoji);
    }
    return (text: buffer.toString(), emoji: emoji);
  }

  /// Стикеры по словам или эмодзи. Порядок: совпало название, потом
  /// синонимы, потом стикеры, где эта эмоция главная, потом побочные.
  /// Запрос из нескольких слов требует совпадения по каждому. [packs] —
  /// искать только в этих паках (установленных: отправлять можно только их).
  List<Sticker> search(String query, {int limit = 40, Set<String>? packs}) {
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
            if ((words.isEmpty || matched[entry.key] == words.length) &&
                (packs == null || packs.contains(entry.key.sticker.packId)))
              entry,
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
