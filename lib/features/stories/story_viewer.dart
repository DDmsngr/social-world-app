import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../../core/debug/app_log.dart';
import '../../core/errors/friendly_error.dart';
import '../../core/media/playback_focus.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/user_avatar.dart';
import '../auth/presentation/providers/auth_providers.dart';
import 'stories.dart';

/// Полноэкранный просмотр сторис: полоски сверху, нажатие справа — дальше,
/// слева — назад, удержание — пауза, свайп вниз — закрыть, свайп вбок —
/// другой автор.
Future<void> showStories(
  BuildContext context, {
  required List<StoryGroup> groups,
  required int initialGroup,
}) {
  if (groups.isEmpty) return Future.value();
  final router = GoRouter.of(context);
  return Navigator.of(context, rootNavigator: true).push<void>(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 160),
      reverseTransitionDuration: const Duration(milliseconds: 120),
      pageBuilder: (_, _, _) => StoryViewerScreen(
        groups: groups,
        initialGroup: initialGroup.clamp(0, groups.length - 1),
        router: router,
      ),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

String storyAgo(DateTime at) {
  final diff = DateTime.now().difference(at);
  if (diff.inMinutes < 1) return 'только что';
  if (diff.inMinutes < 60) return '${diff.inMinutes} мин назад';
  return '${diff.inHours} ч назад';
}

class StoryViewerScreen extends ConsumerStatefulWidget {
  const StoryViewerScreen({
    super.key,
    required this.groups,
    required this.initialGroup,
    required this.router,
  });

  final List<StoryGroup> groups;
  final int initialGroup;
  final GoRouter router;

  @override
  ConsumerState<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends ConsumerState<StoryViewerScreen>
    with SingleTickerProviderStateMixin {
  late List<StoryGroup> _groups = [...widget.groups];
  late int _g = widget.initialGroup;
  late int _s = _groups[_g].startIndex;
  late final AnimationController _progress = AnimationController(vsync: this)
    ..addStatusListener((status) {
      if (status == AnimationStatus.completed) _next();
    });

  VideoPlayerController? _video;
  var _ready = false;
  var _failed = false;

  /// Сколько причин держать паузу сейчас: удержание пальцем, открытое меню.
  var _holds = 0;

  /// Устаревшие загрузки (человек успел нажать «дальше») отбрасываются.
  var _token = 0;

  StoryGroup get _group => _groups[_g];
  Story get _story => _group.stories[_s];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _token++;
    _progress.dispose();
    _releaseVideo();
    super.dispose();
  }

  void _releaseVideo() {
    final video = _video;
    _video = null;
    if (video != null) {
      PlaybackFocus.release(video);
      video.dispose();
    }
  }

  Future<void> _load() async {
    final token = ++_token;
    _progress
      ..stop()
      ..value = 0;
    _releaseVideo();
    setState(() {
      _ready = false;
      _failed = false;
    });

    final story = _story;
    ref.read(storiesProvider.notifier).markViewed(story);

    var length = Duration(seconds: story.durationSec);
    VideoPlayerController? video;
    var failed = false;
    try {
      switch (story.kind) {
        case StoryKind.photo:
          await precacheImage(imageProviderFor(story.mediaUrl!), context);
        case StoryKind.video:
          video = VideoPlayerController.networkUrl(Uri.parse(story.mediaUrl!));
          await video.initialize();
          final real = video.value.duration;
          length = Duration(
            seconds: real.inSeconds.clamp(minStorySeconds, maxVideoSeconds),
          );
        case StoryKind.text:
          break;
      }
    } catch (error) {
      AppLog.add('Сторис не загрузилась: $error');
      failed = true;
      length = const Duration(seconds: 3);
    }

    if (!mounted || token != _token) {
      video?.dispose();
      return;
    }
    _video = video;
    setState(() {
      _ready = true;
      _failed = failed;
    });
    _progress.duration = length;
    if (_holds == 0) _play();
  }

  void _play() {
    _progress.forward();
    final video = _video;
    if (video != null && video.value.isInitialized) {
      PlaybackFocus.claim(video);
      video.play();
    }
  }

  void _pause() {
    _holds++;
    _progress.stop();
    _video?.pause();
  }

  void _resume() {
    if (_holds > 0) _holds--;
    if (_holds == 0 && _ready) _play();
  }

  void _close() => Navigator.of(context).maybePop();

  void _next() {
    if (_s < _group.stories.length - 1) {
      _s++;
    } else if (_g < _groups.length - 1) {
      _g++;
      _s = _group.startIndex;
    } else {
      _close();
      return;
    }
    _load();
  }

  void _prev() {
    if (_s > 0) {
      _s--;
    } else if (_g > 0) {
      _g--;
      _s = 0;
    }
    _load();
  }

  void _nextGroup() {
    if (_g >= _groups.length - 1) return _close();
    _g++;
    _s = _group.startIndex;
    _load();
  }

  void _prevGroup() {
    if (_g == 0) return;
    _g--;
    _s = 0;
    _load();
  }

  Future<void> _delete() async {
    final story = _story;
    _pause();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить историю?'),
        content: const Text('Её не получится вернуть.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      _resume();
      return;
    }
    try {
      await ref.read(storiesProvider.notifier).delete(story);
    } catch (error) {
      AppLog.add('Сторис не удалилась: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(error, fallback: 'Не удалось удалить'))),
      );
      _resume();
      return;
    }
    if (!mounted) return;

    final rest = [...(_group.stories)]..removeAt(_s);
    _holds = 0;
    if (rest.isEmpty) {
      _groups = [..._groups]..removeAt(_g);
      if (_groups.isEmpty) return _close();
      _g = _g.clamp(0, _groups.length - 1);
      _s = 0;
    } else {
      _groups = [
        for (var i = 0; i < _groups.length; i++)
          if (i == _g) _groups[i].copyWith(stories: rest) else _groups[i],
      ];
      _s = _s.clamp(0, rest.length - 1);
    }
    _load();
  }

  Future<void> _showViewers() async {
    final story = _story;
    _pause();
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      builder: (_) => _ViewersSheet(storyId: story.id),
    );
    if (mounted) _resume();
  }

  Future<void> _openPost() async {
    final postId = _story.postId;
    if (postId == null) return;
    final router = widget.router;
    await Navigator.of(context).maybePop();
    router.push('${Routes.posts}/$postId');
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final story = _story;
    final mine = story.authorId == ref.watch(currentUserProvider)?.id;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) {
                if (details.localPosition.dx < media.size.width * 0.3) {
                  _prev();
                } else {
                  _next();
                }
              },
              onLongPressStart: (_) => _pause(),
              onLongPressEnd: (_) => _resume(),
              onLongPressCancel: _resume,
              onVerticalDragEnd: (details) {
                if ((details.primaryVelocity ?? 0) > 400) _close();
              },
              onHorizontalDragEnd: (details) {
                final v = details.primaryVelocity ?? 0;
                if (v < -400) _nextGroup();
                if (v > 400) _prevGroup();
              },
              child: _content(story),
            ),
            // Затемнение под полосками и подписью, чтобы белое читалось на любом фото.
            const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment(0, -0.55),
                    colors: [Color(0x99000000), Color(0x00000000)],
                  ),
                ),
                child: SizedBox.expand(),
              ),
            ),
            Positioned(
              left: 8,
              right: 8,
              top: media.padding.top + 8,
              child: Column(
                children: [
                  _Bars(count: _group.stories.length, current: _s, progress: _progress),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      UserAvatar(
                        name: story.authorName,
                        url: story.authorAvatarUrl,
                        radius: 16,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${story.authorName} · ${storyAgo(story.createdAt)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                        ),
                      ),
                      if (mine)
                        IconButton(
                          onPressed: _delete,
                          tooltip: 'Удалить',
                          icon: const Icon(Icons.delete_outline, color: Colors.white),
                        ),
                      IconButton(
                        onPressed: _close,
                        tooltip: 'Закрыть',
                        icon: const Icon(Icons.close, color: Colors.white),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: media.padding.bottom + 16,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (story.kind != StoryKind.text &&
                      (story.body?.isNotEmpty ?? false))
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        story.body!,
                        maxLines: 5,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 15),
                      ),
                    ),
                  Row(
                    children: [
                      if (story.postId != null)
                        FilledButton.tonal(
                          style: AppButtons.compact,
                          onPressed: _openPost,
                          child: const Text('Открыть пост'),
                        ),
                      const Spacer(),
                      if (mine)
                        TextButton.icon(
                          style: AppButtons.compact,
                          onPressed: _showViewers,
                          icon: const Icon(Icons.visibility_outlined, color: Colors.white),
                          label: Text(
                            '${story.viewCount ?? 0}',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(Story story) {
    if (!_ready) {
      return const Center(child: CircularProgressIndicator(color: Colors.white54));
    }
    if (_failed) {
      return const Center(
        child: Icon(Icons.image_not_supported_outlined, color: Colors.white54, size: 40),
      );
    }
    switch (story.kind) {
      case StoryKind.text:
        return DecoratedBox(
          decoration: BoxDecoration(gradient: storyGradient(story.bg)),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Text(
                story.body ?? '',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                  fontSize: (story.body?.length ?? 0) <= 60 ? 30 : 22,
                ),
              ),
            ),
          ),
        );
      case StoryKind.photo:
        return Center(
          child: Image(
            image: imageProviderFor(story.mediaUrl!),
            fit: BoxFit.contain,
            width: double.infinity,
            height: double.infinity,
          ),
        );
      case StoryKind.video:
        final video = _video;
        if (video == null) return const SizedBox.shrink();
        return Center(
          child: AspectRatio(
            aspectRatio: video.value.aspectRatio,
            child: VideoPlayer(video),
          ),
        );
    }
  }
}

class _Bars extends StatelessWidget {
  const _Bars({required this.count, required this.current, required this.progress});

  final int count;
  final int current;
  final Animation<double> progress;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < count; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: SizedBox(
                  height: 3,
                  child: i == current
                      ? AnimatedBuilder(
                          animation: progress,
                          builder: (_, _) => LinearProgressIndicator(
                            value: progress.value,
                            backgroundColor: Colors.white30,
                            valueColor: const AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                      : ColoredBox(color: i < current ? Colors.white : Colors.white30),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ViewersSheet extends ConsumerWidget {
  const _ViewersSheet({required this.storyId});

  final String storyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      child: FutureBuilder<List<StoryViewer>>(
        future: ref.read(storiesRepositoryProvider).viewers(storyId),
        builder: (context, snapshot) {
          final viewers = snapshot.data;
          if (snapshot.hasError) {
            return const SizedBox(
              height: 120,
              child: Center(child: Text('Не удалось загрузить')),
            );
          }
          if (viewers == null) {
            return const SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (viewers.isEmpty) {
            return const SizedBox(
              height: 120,
              child: Center(child: Text('Пока никто не смотрел')),
            );
          }
          return ListView(
            shrinkWrap: true,
            children: [
              for (final viewer in viewers)
                ListTile(
                  leading: UserAvatar(name: viewer.name, url: viewer.avatarUrl),
                  title: Text(viewer.name),
                  subtitle: Text(storyAgo(viewer.viewedAt)),
                ),
            ],
          );
        },
      ),
    );
  }
}
