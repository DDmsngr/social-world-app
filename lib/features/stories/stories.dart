import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/env.dart';
import '../../core/debug/app_log.dart';
import '../../core/media/media_uploader.dart';
import '../auth/presentation/providers/auth_providers.dart';

enum StoryKind {
  photo,
  video,
  text;

  static StoryKind parse(Object? raw) =>
      values.firstWhere((k) => k.name == raw, orElse: () => StoryKind.text);
}

/// Кому видна сторис. Сервер проверяет это сам (политика и stories_feed).
enum StoryAudience {
  everyone('public', 'Всем'),
  followers('followers', 'Подписчикам');

  const StoryAudience(this.wire, this.label);
  final String wire;
  final String label;
}

/// Время показа фото и текста: от [minSeconds] до [maxSeconds]. У видео оно
/// равно длине ролика, но не больше [maxVideoSeconds].
const minStorySeconds = 3;
const maxStorySeconds = 15;
const defaultStorySeconds = 5;
const maxVideoSeconds = 30;

/// Фоны текстовых сторис: номер хранится в базе, цвета — здесь.
const storyBackgrounds = <List<Color>>[
  [Color(0xFFEA2249), Color(0xFFFF7A59)],
  [Color(0xFF5B5BD6), Color(0xFF8E7CFF)],
  [Color(0xFF0E9F8E), Color(0xFF4ADE9C)],
  [Color(0xFFF59E0B), Color(0xFFFB7185)],
  [Color(0xFF2563EB), Color(0xFF22B8CF)],
  [Color(0xFF7C3AED), Color(0xFFEC4899)],
  [Color(0xFF111827), Color(0xFF4B5563)],
  [Color(0xFF831843), Color(0xFFBE123C)],
];

LinearGradient storyGradient(int bg) => LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: storyBackgrounds[bg.abs() % storyBackgrounds.length],
);

class Story {
  const Story({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.kind,
    required this.createdAt,
    this.authorAvatarUrl,
    this.mediaUrl,
    this.body,
    this.bg = 0,
    this.durationSec = defaultStorySeconds,
    this.postId,
    this.viewed = false,
    this.viewCount,
  });

  final String id;
  final String authorId;
  final String authorName;
  final String? authorAvatarUrl;
  final StoryKind kind;
  final String? mediaUrl;
  final String? body;
  final int bg;
  final int durationSec;
  final String? postId;
  final DateTime createdAt;
  final bool viewed;

  /// Только у своих сторис.
  final int? viewCount;

  Story copyWith({bool? viewed}) => Story(
    id: id,
    authorId: authorId,
    authorName: authorName,
    authorAvatarUrl: authorAvatarUrl,
    kind: kind,
    mediaUrl: mediaUrl,
    body: body,
    bg: bg,
    durationSec: durationSec,
    postId: postId,
    createdAt: createdAt,
    viewed: viewed ?? this.viewed,
    viewCount: viewCount,
  );

  factory Story.fromRow(Map<String, dynamic> row) => Story(
    id: row['id'] as String,
    authorId: row['author_id'] as String,
    authorName: row['author_name'] as String? ?? 'Без имени',
    authorAvatarUrl: row['author_avatar'] as String?,
    kind: StoryKind.parse(row['kind']),
    mediaUrl: row['media_url'] as String?,
    body: row['body'] as String?,
    bg: (row['bg'] as num?)?.toInt() ?? 0,
    durationSec: ((row['duration_sec'] as num?)?.toInt() ?? defaultStorySeconds)
        .clamp(minStorySeconds, maxVideoSeconds),
    postId: row['post_id'] as String?,
    createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
    viewed: row['viewed'] as bool? ?? false,
    viewCount: (row['view_count'] as num?)?.toInt(),
  );
}

/// Все живые сторис одного человека, от старой к новой.
class StoryGroup {
  const StoryGroup({
    required this.authorId,
    required this.authorName,
    required this.stories,
    required this.isMine,
    this.authorAvatarUrl,
    this.followed = false,
  });

  final String authorId;
  final String authorName;
  final String? authorAvatarUrl;
  final List<Story> stories;
  final bool isMine;
  final bool followed;

  bool get allViewed => stories.every((s) => s.viewed);

  /// С чего начинать показ: с первой непросмотренной, иначе с начала.
  int get startIndex {
    final i = stories.indexWhere((s) => !s.viewed);
    return i < 0 ? 0 : i;
  }

  /// Что нарисовать на плитке в полосе: следующая к просмотру.
  Story get cover => stories[startIndex];

  StoryGroup copyWith({List<Story>? stories}) => StoryGroup(
    authorId: authorId,
    authorName: authorName,
    authorAvatarUrl: authorAvatarUrl,
    stories: stories ?? this.stories,
    isMine: isMine,
    followed: followed,
  );
}

/// Раскладывает ленту по авторам: сначала свои, затем те, у кого есть
/// непросмотренное (подписки впереди чужих), в конце — всё просмотренное.
List<StoryGroup> groupStories(
  List<Story> stories, {
  required String? me,
  Set<String> followed = const {},
}) {
  final byAuthor = <String, List<Story>>{};
  for (final story in stories) {
    byAuthor.putIfAbsent(story.authorId, () => []).add(story);
  }
  final groups = [
    for (final entry in byAuthor.entries)
      StoryGroup(
        authorId: entry.key,
        authorName: entry.value.first.authorName,
        authorAvatarUrl: entry.value.first.authorAvatarUrl,
        stories: entry.value,
        isMine: entry.key == me,
        followed: followed.contains(entry.key),
      ),
  ];
  int rank(StoryGroup g) {
    if (g.isMine) return 0;
    if (!g.allViewed) return g.followed ? 1 : 2;
    return 3;
  }

  groups.sort((a, b) {
    final byRank = rank(a).compareTo(rank(b));
    if (byRank != 0) return byRank;
    // Внутри ранга — у кого сторис свежее.
    return b.stories.last.createdAt.compareTo(a.stories.last.createdAt);
  });
  return groups;
}

class StoryViewer {
  const StoryViewer({required this.name, required this.viewedAt, this.avatarUrl});

  final String name;
  final String? avatarUrl;
  final DateTime viewedAt;
}

class StoriesRepository {
  StoriesRepository(this._client);

  /// null — приложение без сервера (заглушка): сторис просто нет.
  final SupabaseClient? _client;

  bool get available => _client != null;

  Future<({List<Story> stories, Set<String> followed})> load() async {
    final client = _client;
    if (client == null) return (stories: const <Story>[], followed: const <String>{});
    final rows = (await client.rpc('stories_feed') as List).cast<Map<String, dynamic>>();
    return (
      stories: [for (final row in rows) Story.fromRow(row)],
      followed: {
        for (final row in rows)
          if (row['followed'] == true) row['author_id'] as String,
      },
    );
  }

  /// Фото или видео уходит в тот же бакет, что и посты.
  Future<String> uploadMedia(
    String localPath, {
    void Function(double)? onProgress,
    void Function(String stage)? onStage,
  }) => MediaUploader(
    _client!,
    bucket: 'post-media',
  ).upload(localPath, onProgress: onProgress, onStage: onStage);

  Future<void> create({
    required StoryKind kind,
    required StoryAudience audience,
    String? mediaUrl,
    String? body,
    int bg = 0,
    int durationSec = defaultStorySeconds,
    String? postId,
  }) async {
    await _client!.rpc(
      'create_story',
      params: {
        'in_kind': kind.name,
        'in_media_url': mediaUrl,
        'in_body': body,
        'in_bg': bg,
        'in_duration': durationSec,
        'in_visibility': audience.wire,
        'in_post': postId,
      },
    );
  }

  Future<void> delete(String storyId) async {
    await _client!.from('stories').delete().eq('id', storyId);
  }

  Future<void> markViewed(String storyId) async {
    await _client?.rpc('mark_story_viewed', params: {'in_story': storyId});
  }

  Future<List<StoryViewer>> viewers(String storyId) async {
    final rows =
        (await _client!.rpc('story_viewers', params: {'in_story': storyId}) as List)
            .cast<Map<String, dynamic>>();
    return [
      for (final row in rows)
        StoryViewer(
          name: row['display_name'] as String? ?? 'Без имени',
          avatarUrl: row['avatar_url'] as String?,
          viewedAt: DateTime.parse(row['viewed_at'] as String).toLocal(),
        ),
    ];
  }
}

final storiesRepositoryProvider = Provider<StoriesRepository>((ref) {
  ref.keepAlive();
  return StoriesRepository(Env.isConfigured ? Supabase.instance.client : null);
});

class StoriesController extends AsyncNotifier<List<StoryGroup>> {
  @override
  Future<List<StoryGroup>> build() async {
    ref.keepAlive();
    final me = ref.watch(currentUserProvider)?.id;
    if (me == null) return const [];
    return _load(me);
  }

  Future<List<StoryGroup>> _load(String me) async {
    final result = await ref.read(storiesRepositoryProvider).load();
    return groupStories(result.stories, me: me, followed: result.followed);
  }

  /// Тихое обновление: старая полоса остаётся на экране, пока идёт запрос.
  Future<void> refresh() async {
    final me = ref.read(currentUserProvider)?.id;
    if (me == null) return;
    try {
      state = AsyncData(await _load(me));
    } catch (error) {
      AppLog.add('Сторис не обновились: $error');
    }
  }

  /// Отметка «просмотрено» применяется на месте и уходит на сервер.
  Future<void> markViewed(Story story) async {
    final me = ref.read(currentUserProvider)?.id;
    if (story.viewed || story.authorId == me) return;
    state = AsyncData([
      for (final group in state.value ?? const <StoryGroup>[])
        if (group.authorId == story.authorId)
          group.copyWith(
            stories: [
              for (final s in group.stories) if (s.id == story.id) s.copyWith(viewed: true) else s,
            ],
          )
        else
          group,
    ]);
    try {
      await ref.read(storiesRepositoryProvider).markViewed(story.id);
    } catch (error) {
      AppLog.add('Просмотр сторис не записался: $error');
    }
  }

  Future<void> delete(Story story) async {
    await ref.read(storiesRepositoryProvider).delete(story.id);
    await refresh();
  }
}

final storiesProvider = AsyncNotifierProvider<StoriesController, List<StoryGroup>>(
  StoriesController.new,
);
