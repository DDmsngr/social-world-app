import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../../core/debug/app_log.dart';
import '../../core/errors/friendly_error.dart';
import '../../core/media/media_kind.dart';
import '../../core/media/video_compressor.dart';
import '../../core/text/markdown_preview.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/user_avatar.dart';
import '../feed/domain/entities/post.dart';
import 'stories.dart';

/// Что войдёт в сторис. Файл с телефона ([localPath]) перед публикацией
/// загружается; для сторис из поста медиа уже в хранилище ([remoteUrl]).
class StoryDraft {
  const StoryDraft({
    required this.kind,
    this.localPath,
    this.remoteUrl,
    this.text = '',
    this.bg = 0,
    this.postId,
    this.audience = StoryAudience.everyone,
  });

  final StoryKind kind;
  final String? localPath;
  final String? remoteUrl;
  final String text;
  final int bg;
  final String? postId;
  final StoryAudience audience;
}

void _toast(BuildContext context, String text) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

Future<bool?> _openComposer(BuildContext context, StoryDraft draft) =>
    Navigator.of(context, rootNavigator: true).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => StoryComposerScreen(draft: draft),
      ),
    );

/// «+» в полосе сторис: выбор — фото, снимок, видео или текст.
Future<void> addStory(BuildContext context, WidgetRef ref) async {
  if (!ref.read(storiesRepositoryProvider).available) {
    _toast(context, 'Истории доступны только при подключении к серверу');
    return;
  }
  final choice = await showModalBottomSheet<String>(
    context: context,
    useRootNavigator: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (value, icon, label) in const [
            ('photo', Icons.photo_outlined, 'Фото из галереи'),
            ('camera', Icons.photo_camera_outlined, 'Снять фото'),
            ('video', Icons.videocam_outlined, 'Видео (до 30 секунд)'),
            ('text', Icons.text_fields, 'Текст на цветном фоне'),
          ])
            ListTile(
              leading: Icon(icon),
              title: Text(label),
              onTap: () => Navigator.pop(context, value),
            ),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;

  final picker = ImagePicker();
  StoryDraft? draft;
  switch (choice) {
    case 'photo' || 'camera':
      final file = await picker.pickImage(
        source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1600,
      );
      if (file != null) draft = StoryDraft(kind: StoryKind.photo, localPath: file.path);
    case 'video':
      final file = await picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(seconds: maxVideoSeconds),
      );
      if (file != null) {
        final size = await File(file.path).length();
        if (size > maxVideoSourceBytes) {
          if (context.mounted) _toast(context, videoTooBigMessage(size));
          return;
        }
        draft = StoryDraft(kind: StoryKind.video, localPath: file.path);
      }
    default:
      draft = const StoryDraft(kind: StoryKind.text);
  }
  if (draft == null || !context.mounted) return;
  final published = await _openComposer(context, draft);
  if (published == true && context.mounted) _toast(context, 'История опубликована');
}

/// «В сторис» у своего поста любого типа: фото или видео поста, а у статьи,
/// маршрута и текстового поста — заголовок или начало текста на цветном фоне.
Future<void> storyFromPost(BuildContext context, WidgetRef ref, Post post) async {
  if (!ref.read(storiesRepositoryProvider).available) {
    _toast(context, 'Истории доступны только при подключении к серверу');
    return;
  }
  final title = post.title?.trim();
  final raw = (title != null && title.isNotEmpty)
      ? title
      : markdownPreview(post.body ?? '', maxChars: 200);
  final text = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  final audience = post.visibility == PostVisibility.everyone
      ? StoryAudience.everyone
      : StoryAudience.followers;

  final photo = post.photoUrls.isEmpty ? null : post.photoUrls.first;
  final video = post.mediaUrls.where(isVideoUrl).firstOrNull;
  final draft = photo != null
      ? StoryDraft(
          kind: StoryKind.photo,
          remoteUrl: photo,
          text: text,
          postId: post.id,
          audience: audience,
        )
      : video != null
      ? StoryDraft(
          kind: StoryKind.video,
          remoteUrl: video,
          text: text,
          postId: post.id,
          audience: audience,
        )
      : StoryDraft(
          kind: StoryKind.text,
          text: text.isEmpty ? post.authorName : text,
          bg: post.id.hashCode.abs() % storyBackgrounds.length,
          postId: post.id,
          audience: audience,
        );
  final published = await _openComposer(context, draft);
  if (published == true && context.mounted) _toast(context, 'История опубликована');
}

class StoryComposerScreen extends ConsumerStatefulWidget {
  const StoryComposerScreen({super.key, required this.draft});

  final StoryDraft draft;

  @override
  ConsumerState<StoryComposerScreen> createState() => _StoryComposerScreenState();
}

class _StoryComposerScreenState extends ConsumerState<StoryComposerScreen> {
  late final _text = TextEditingController(text: widget.draft.text);
  late var _bg = widget.draft.bg;
  late var _audience = widget.draft.audience;
  var _seconds = defaultStorySeconds.toDouble();

  VideoPlayerController? _video;
  var _busy = false;
  String _label = '';
  double _progress = 0;

  StoryKind get _kind => widget.draft.kind;

  @override
  void initState() {
    super.initState();
    if (_kind == StoryKind.video) _initVideo();
  }

  @override
  void dispose() {
    _text.dispose();
    _video?.dispose();
    super.dispose();
  }

  Future<void> _initVideo() async {
    final draft = widget.draft;
    final controller = draft.localPath != null
        ? VideoPlayerController.file(File(draft.localPath!))
        : VideoPlayerController.networkUrl(Uri.parse(draft.remoteUrl!));
    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(0);
      await controller.play();
    } catch (error) {
      AppLog.add('Видео сторис не открылось: $error');
    }
    if (!mounted) {
      await controller.dispose();
      return;
    }
    setState(() => _video = controller);
  }

  int? get _videoSeconds {
    final video = _video;
    if (video == null || !video.value.isInitialized) return null;
    return video.value.duration.inSeconds;
  }

  bool get _tooLong => (_videoSeconds ?? 0) > maxVideoSeconds;

  bool get _canPublish {
    if (_busy) return false;
    return switch (_kind) {
      StoryKind.text => _text.text.trim().isNotEmpty,
      StoryKind.video => _video != null && _video!.value.isInitialized && !_tooLong,
      StoryKind.photo => true,
    };
  }

  Future<void> _publish() async {
    final repo = ref.read(storiesRepositoryProvider);
    final draft = widget.draft;
    setState(() {
      _busy = true;
      _label = '';
      _progress = 0;
    });
    try {
      var url = draft.remoteUrl;
      if (draft.localPath != null) {
        _label = _kind == StoryKind.video ? 'Загружаем видео' : 'Загружаем фото';
        url = await repo.uploadMedia(
          draft.localPath!,
          onProgress: (p) {
            if (mounted) setState(() => _progress = p);
          },
          onStage: (stage) {
            if (mounted) setState(() => _label = stage);
          },
        );
      }
      await repo.create(
        kind: _kind,
        audience: _audience,
        mediaUrl: url,
        body: _text.text.trim(),
        bg: _bg,
        durationSec: _kind == StoryKind.video
            ? (_videoSeconds ?? defaultStorySeconds).clamp(minStorySeconds, maxVideoSeconds)
            : _seconds.round(),
        postId: draft.postId,
      );
      await ref.read(storiesProvider.notifier).refresh();
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      AppLog.add('История не опубликовалась: $error');
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(context, friendlyError(error, fallback: 'Не удалось опубликовать'));
    }
  }

  Widget _preview() {
    final draft = widget.draft;
    switch (_kind) {
      case StoryKind.text:
        return DecoratedBox(
          decoration: BoxDecoration(gradient: storyGradient(_bg)),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: TextField(
                controller: _text,
                maxLength: 280,
                maxLines: null,
                textAlign: TextAlign.center,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 24,
                  height: 1.25,
                ),
                cursorColor: Colors.white,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  counterStyle: TextStyle(color: Colors.white70),
                  hintText: 'Что хотите рассказать?',
                  hintStyle: TextStyle(color: Colors.white54),
                ),
              ),
            ),
          ),
        );
      case StoryKind.photo:
        return ColoredBox(
          color: Colors.black,
          child: draft.localPath != null
              ? Image.file(File(draft.localPath!), fit: BoxFit.contain)
              : Image(image: imageProviderFor(draft.remoteUrl!), fit: BoxFit.contain),
        );
      case StoryKind.video:
        final video = _video;
        return ColoredBox(
          color: Colors.black,
          child: video == null || !video.value.isInitialized
              ? const Center(child: CircularProgressIndicator())
              : Center(
                  child: AspectRatio(
                    aspectRatio: video.value.aspectRatio,
                    child: VideoPlayer(video),
                  ),
                ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.46;

    return Scaffold(
      appBar: AppBar(title: const Text('Новая история')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Center(
            child: SizedBox(
              height: height,
              child: AspectRatio(
                aspectRatio: 9 / 16,
                child: ClipRRect(borderRadius: BorderRadius.circular(18), child: _preview()),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_kind == StoryKind.text)
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: storyBackgrounds.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (_, i) => GestureDetector(
                  onTap: () => setState(() => _bg = i),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: storyGradient(i),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _bg == i ? Colors.white : Colors.transparent,
                        width: 2.5,
                      ),
                    ),
                  ),
                ),
              ),
            )
          else
            TextField(
              controller: _text,
              maxLength: 200,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(hintText: 'Подпись (по желанию)'),
            ),
          const SizedBox(height: 8),
          if (_kind == StoryKind.video) ...[
            Text(
              _tooLong
                  ? 'Ролик длиннее $maxVideoSeconds секунд — выберите покороче'
                  : _videoSeconds == null
                  ? ' '
                  : 'Покажем весь ролик: $_videoSeconds с',
              style: TextStyle(
                color: _tooLong ? Theme.of(context).colorScheme.error : AppColors.textDim,
              ),
            ),
          ] else ...[
            Row(
              children: [
                Text('Показывать ${_seconds.round()} с', style: TextStyle(color: AppColors.textDim)),
                Expanded(
                  child: Slider(
                    value: _seconds,
                    min: minStorySeconds.toDouble(),
                    max: maxStorySeconds.toDouble(),
                    divisions: maxStorySeconds - minStorySeconds,
                    label: '${_seconds.round()} с',
                    onChanged: _busy ? null : (v) => setState(() => _seconds = v),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 4),
          SegmentedButton<StoryAudience>(
            showSelectedIcon: false,
            segments: [
              for (final a in StoryAudience.values) ButtonSegment(value: a, label: Text(a.label)),
            ],
            selected: {_audience},
            onSelectionChanged: _busy ? null : (s) => setState(() => _audience = s.first),
          ),
          const SizedBox(height: 6),
          Text(
            'История пропадёт через 24 часа.',
            style: TextStyle(fontSize: 12, color: AppColors.textFaint),
          ),
          const SizedBox(height: 16),
          if (_busy && _label.isNotEmpty) ...[
            LinearProgressIndicator(value: _progress == 0 ? null : _progress),
            const SizedBox(height: 6),
            Text(_label, style: TextStyle(fontSize: 12, color: AppColors.textDim)),
            const SizedBox(height: 10),
          ],
          FilledButton(
            onPressed: _canPublish ? _publish : null,
            child: _busy && _label.isEmpty
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Опубликовать'),
          ),
        ],
      ),
    );
  }
}
