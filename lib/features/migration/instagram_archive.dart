import 'dart:convert';

/// Разбор выгрузки данных из другой соцсети (zip с JSON). Здесь только чистая
/// логика над уже прочитанным JSON: чтение самого архива — в `archive_reader.dart`.

/// Выгрузка хранит текст как UTF-8 байты, записанные символами Latin-1
/// (`Ð\u009f` вместо «П»). Возвращает нормальную строку; обычный текст,
/// где уже есть символы выше Latin-1, не трогает.
String fixText(String value) {
  for (final unit in value.codeUnits) {
    if (unit > 0xFF) return value;
  }
  try {
    return utf8.decode(value.codeUnits);
  } on FormatException {
    return value;
  }
}

class ImportedMedia {
  const ImportedMedia(this.entry, {required this.video});

  /// Путь файла внутри архива.
  final String entry;
  final bool video;
}

class ImportedPost {
  const ImportedPost({required this.media, required this.caption, this.takenAt});

  final List<ImportedMedia> media;
  final String caption;
  final DateTime? takenAt;
}

class ImportedContact {
  const ImportedContact(
    this.handle, {
    this.followsMe = false,
    this.iFollow = false,
  });

  final String handle;
  final bool followsMe;
  final bool iFollow;

  bool get mutual => followsMe && iFollow;
}

class ParsedExport {
  const ParsedExport({
    required this.posts,
    required this.contacts,
    this.profilePhotoEntry,
    this.handle,
  });

  final List<ImportedPost> posts;
  final List<ImportedContact> contacts;
  final String? profilePhotoEntry;

  /// Свой ник в прежней сети, если удалось определить.
  final String? handle;

  int get mediaCount => posts.fold(0, (sum, p) => sum + p.media.length);
}

const _videoExtensions = ['.mp4', '.mov', '.m4v', '.webm'];

bool _isVideo(String path) {
  final lower = path.toLowerCase();
  return _videoExtensions.any(lower.endsWith);
}

/// Файлы с публикациями: посты, архив и ролики (сторис живут сутки — не берём).
bool isPostsFile(String entry) {
  return RegExp(r'(^|/)(posts_\d+|archived_posts|reels)\.json$').hasMatch(entry);
}

bool isFollowersFile(String entry) =>
    RegExp(r'(^|/)followers_\d+\.json$').hasMatch(entry);

bool isFollowingFile(String entry) => entry.endsWith('/following.json');

bool isProfilePhotosFile(String entry) =>
    entry.endsWith('/profile_photos.json');

DateTime? _seconds(Object? value) =>
    value is int && value > 0
        ? DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true)
        : null;

/// Элементы публикаций: файл бывает списком (posts_1.json) или объектом с
/// одним списком внутри (reels.json, archived_posts.json).
List<Map<String, dynamic>> _entries(Object? json) {
  Object? list = json;
  if (json is Map) {
    list = null;
    for (final value in json.values) {
      if (value is List) {
        list = value;
        break;
      }
    }
  }
  if (list is! List) return const [];
  return [
    for (final item in list)
      if (item is Map) item.cast<String, dynamic>(),
  ];
}

List<ImportedPost> parsePosts(Object? json) {
  final posts = <ImportedPost>[];
  for (final item in _entries(json)) {
    final mediaRaw = item['media'];
    if (mediaRaw is! List) continue;
    final media = <ImportedMedia>[];
    String? caption = item['title'] as String?;
    DateTime? taken = _seconds(item['creation_timestamp']);
    for (final m in mediaRaw) {
      if (m is! Map) continue;
      final uri = m['uri'];
      if (uri is! String || uri.isEmpty) continue;
      media.add(ImportedMedia(uri, video: _isVideo(uri)));
      caption ??= m['title'] as String?;
      taken ??= _seconds(m['creation_timestamp']);
    }
    if (media.isEmpty) continue;
    posts.add(
      ImportedPost(
        media: media,
        caption: fixText((caption ?? '').trim()),
        takenAt: taken,
      ),
    );
  }
  return posts;
}

String? _handleOf(Map<String, dynamic> item) {
  final data = item['string_list_data'];
  if (data is List && data.isNotEmpty && data.first is Map) {
    final value = (data.first as Map)['value'];
    if (value is String && value.isNotEmpty) return value;
  }
  final title = item['title'];
  return title is String && title.isNotEmpty ? title : null;
}

List<String> parseFollowers(Object? json) => [
  for (final item in _entries(json)) ?_handleOf(item),
];

List<String> parseFollowing(Object? json) {
  final list = json is Map ? json['relationships_following'] : json;
  return [for (final item in _entries(list)) ?_handleOf(item)];
}

/// Подписчики и подписки в один список без повторов. Ники приводятся к
/// нижнему регистру: на них сравнивают, а не показывают.
List<ImportedContact> mergeContacts({
  required Iterable<String> followers,
  required Iterable<String> following,
}) {
  final followerSet = {for (final h in followers) h.toLowerCase()};
  final followingSet = {for (final h in following) h.toLowerCase()};
  final all = {...followerSet, ...followingSet}.toList()..sort();
  return [
    for (final h in all)
      ImportedContact(
        h,
        followsMe: followerSet.contains(h),
        iFollow: followingSet.contains(h),
      ),
  ];
}

String? parseProfilePhoto(Object? json) {
  if (json is! Map) return null;
  final list = json['ig_profile_picture'];
  if (list is List && list.isNotEmpty && list.first is Map) {
    final uri = (list.first as Map)['uri'];
    if (uri is String && uri.isNotEmpty) return uri;
  }
  return null;
}

/// Свой ник: из имени файла выгрузки (`<сеть>-<ник>-<дата>-<код>.zip`).
String? handleFromArchiveName(String fileName) {
  final name = fileName.split(RegExp(r'[\\/]')).last;
  final match = RegExp(
    r'^[A-Za-z]+-(.+)-\d{4}-\d{2}-\d{2}-[A-Za-z0-9]+\.zip$',
  ).firstMatch(name);
  return match?.group(1);
}

/// Сколько фото и видео влезает в одну публикацию ChaWo.
const maxMediaPerPost = 4;

/// Короткая подпись — момент; длинная не влезет в 500 знаков, её публикуем
/// статьёй с заголовком из первой строки.
const maxMomentCaption = 500;

String articleTitle(String caption) {
  final first = caption.split('\n').firstWhere(
    (line) => line.trim().isNotEmpty,
    orElse: () => 'Публикация',
  );
  final clean = first.trim();
  return clean.length <= 80 ? clean : '${clean.substring(0, 79)}…';
}
