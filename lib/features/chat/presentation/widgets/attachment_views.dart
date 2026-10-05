import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:open_filex/open_filex.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/debug/app_log.dart';
import '../../../../core/media/photo_viewer.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/chat_message.dart';
import '../providers/chat_providers.dart';

/// Вложение сообщения: скачивается (и расшифровывается) при показе, дальше
/// живёт в кэше на устройстве. Что рисовать, решает тип сообщения.
class AttachmentView extends ConsumerStatefulWidget {
  const AttachmentView({
    super.key,
    required this.message,
    required this.mine,
    this.onMore,
  });

  final ChatMessage message;
  final bool mine;

  /// «⋮» в полноэкранном просмотре — то же меню, что по долгому тапу.
  final Future<bool> Function(BuildContext context)? onMore;

  @override
  ConsumerState<AttachmentView> createState() => _AttachmentViewState();
}

class _AttachmentViewState extends ConsumerState<AttachmentView> {
  Future<String>? _file;

  /// Тяжёлое (видео, файлы) качаем по тапу, остальное — сразу.
  bool get _autoLoad => switch (widget.message.kind) {
    MessageKind.image || MessageKind.videoNote || MessageKind.voice => true,
    _ => false,
  };

  @override
  void initState() {
    super.initState();
    if (_autoLoad) _load();
  }

  @override
  void didUpdateWidget(AttachmentView old) {
    super.didUpdateWidget(old);
    if (old.message.id != widget.message.id) {
      _file = null;
      if (_autoLoad) _load();
    }
  }

  Future<String> _load() {
    final future = ref
        .read(chatRepositoryProvider)
        .attachmentFile(widget.message);
    future.catchError((Object error) {
      AppLog.add('Вложение не скачалось: $error');
      return '';
    });
    setState(() => _file = future);
    return future;
  }

  Future<void> _openWith(Future<void> Function(String path) action) async {
    try {
      final path = await (_file ?? _load());
      await action(path);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось открыть вложение')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final attachment = message.attachment!;

    return switch (message.kind) {
      MessageKind.image => _Loaded(
        future: _file,
        onRetry: _load,
        placeholderSize: const Size(220, 220),
        builder: (path) => GestureDetector(
          onTap: () => showPhotoViewer(
            context,
            urls: [path],
            caption: message.text,
            onMore: widget.onMore,
          ),
          child: ChatPhoto(path: path),
        ),
      ),
      MessageKind.videoNote => _Loaded(
        future: _file,
        onRetry: _load,
        placeholderSize: const Size(200, 200),
        circle: true,
        builder: (path) => VideoNotePlayer(filePath: path),
      ),
      MessageKind.voice => _Loaded(
        future: _file,
        onRetry: _load,
        placeholderSize: const Size(230, 44),
        builder: (path) => VoiceMessagePlayer(
          messageId: message.id,
          filePath: path,
          attachment: attachment,
          mine: widget.mine,
        ),
      ),
      // Видео — превью с кнопкой «play», а не строка файла.
      MessageKind.video => SizedBox(
        width: 260,
        child: VideoPreview(message: message),
      ),
      _ => _FileTile(
        icon: iconForMime(attachment.mime),
        title: attachment.name ?? 'Файл',
        subtitle: formatFileSize(attachment.size),
        mine: widget.mine,
        loading: _file,
        onTap: () => _openWith((path) async {
          final messenger = ScaffoldMessenger.of(context);
          final result = await OpenFilex.open(path, type: attachment.mime);
          if (result.type != ResultType.done) {
            messenger.showSnackBar(
              SnackBar(
                content: Text(
                  'Нет приложения, чтобы открыть файл: ${result.message}',
                ),
              ),
            );
          }
        }),
      ),
    };
  }

}

/// Фото в пузыре по своим пропорциям. Раньше `Image.file` стоял в
/// ConstrainedBox без размеров: до раскодирования картинка не знала своих
/// пропорций, пузырь раздувался по высоте, а фото рисовалось обрезанной
/// полосой сверху с пустым низом. Теперь сначала узнаём размер файла, потом
/// задаём точную рамку: не шире 240 и не выше 320, пропорции сохранены.
class ChatPhoto extends StatefulWidget {
  const ChatPhoto({super.key, required this.path});

  final String path;

  static const maxWidth = 240.0;
  static const maxHeight = 320.0;

  /// Рамка под картинку размера [image] в пределах [maxWidth]×[maxHeight].
  static Size fit(Size image) {
    if (image.width <= 0 || image.height <= 0) {
      return const Size(maxWidth, maxWidth);
    }
    final scale = [
      maxWidth / image.width,
      maxHeight / image.height,
    ].reduce((a, b) => a < b ? a : b);
    // Очень узкие и очень широкие картинки не сжимаем в нитку.
    return Size(
      (image.width * scale).clamp(96.0, maxWidth),
      (image.height * scale).clamp(96.0, maxHeight),
    );
  }

  @override
  State<ChatPhoto> createState() => _ChatPhotoState();
}

class _ChatPhotoState extends State<ChatPhoto> {
  Size? _size;
  ImageStream? _stream;
  late final ImageStreamListener _listener = ImageStreamListener(
    (info, _) {
      if (!mounted) return;
      setState(() {
        _size = ChatPhoto.fit(
          Size(info.image.width.toDouble(), info.image.height.toDouble()),
        );
      });
    },
    onError: (error, _) {
      AppLog.add('Фото не раскодировалось: $error');
      if (mounted) setState(() => _size = ChatPhoto.fit(Size.zero));
    },
  );

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(ChatPhoto old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) {
      _stream?.removeListener(_listener);
      _size = null;
      _resolve();
    }
  }

  void _resolve() {
    _stream = FileImage(File(widget.path)).resolve(ImageConfiguration.empty)
      ..addListener(_listener);
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = _size ?? const Size(ChatPhoto.maxWidth, ChatPhoto.maxWidth);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: _size == null
            ? ColoredBox(color: AppColors.ink)
            : Image.file(File(widget.path), fit: BoxFit.cover),
      ),
    );
  }
}

class _Loaded extends StatelessWidget {
  const _Loaded({
    required this.future,
    required this.onRetry,
    required this.builder,
    required this.placeholderSize,
    this.circle = false,
  });

  final Future<String>? future;
  final VoidCallback onRetry;
  final Widget Function(String path) builder;
  final Size placeholderSize;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: future,
      builder: (context, snapshot) {
        final path = snapshot.data;
        if (path != null && path.isNotEmpty) return builder(path);
        final failed =
            snapshot.hasError ||
            (snapshot.connectionState == ConnectionState.done);
        return Container(
          width: placeholderSize.width,
          height: placeholderSize.height,
          decoration: BoxDecoration(
            color: AppColors.ink,
            shape: circle ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: circle ? null : BorderRadius.circular(12),
          ),
          child: Center(
            child: failed
                ? IconButton(
                    onPressed: onRetry,
                    tooltip: 'Повторить',
                    icon: Icon(Icons.refresh, color: AppColors.textDim),
                  )
                : const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
          ),
        );
      },
    );
  }
}

class _FileTile extends StatelessWidget {
  const _FileTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.mine,
    required this.loading,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool mine;
  final Future<String>? loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = mine ? AppColors.onBubbleMine : AppColors.text;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 230,
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: FutureBuilder<String>(
                future: loading,
                builder: (context, snapshot) =>
                    loading != null &&
                        snapshot.connectionState != ConnectionState.done
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(icon, color: color),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: color.withValues(alpha: 0.7),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Кружок: без звука и по кругу, как в Telegram; тап — со звуком с начала,
/// ещё тап — пауза.
class VideoNotePlayer extends ConsumerStatefulWidget {
  const VideoNotePlayer({super.key, required this.filePath});

  final String filePath;

  @override
  ConsumerState<VideoNotePlayer> createState() => _VideoNotePlayerState();
}

class _VideoNotePlayerState extends ConsumerState<VideoNotePlayer> {
  static const _size = 200.0;
  late final VideoPlayerController _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.filePath))
      ..addListener(_onTick)
      ..initialize()
          .then((_) {
            _controller
              ..setLooping(true)
              ..setVolume(0)
              ..play();
            if (mounted) setState(() => _ready = true);
          })
          .catchError((Object error) {
            AppLog.add('Кружок не воспроизводится: $error');
          });
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onTick)
      ..dispose();
    super.dispose();
  }

  // ── перемотка по кольцу ────────────────────────────────────────────────
  // Палец у края кружка ведёт ползунок по кольцу, как стрелку часов: верх —
  // начало, полный круг — конец. Пока тянем, ролик на паузе.
  bool _scrubbing = false;
  bool _wasPlaying = false;
  double _scrubFraction = 0;

  /// Касание в полосе кольца (внешние ~15% радиуса) и звук включён.
  bool _onRing(Offset local) {
    if (!_ready || _controller.value.volume == 0) return false;
    final r = _size / 2;
    final d = (local - Offset(r, r)).distance;
    return d >= r * 0.78 && d <= r * 1.18;
  }

  double _fractionAt(Offset local) {
    const r = _size / 2;
    final dx = local.dx - r;
    final dy = local.dy - r;
    var angle = math.atan2(dx, -dy); // от верха по часовой, -π..π
    if (angle < 0) angle += 2 * math.pi;
    var fraction = angle / (2 * math.pi);
    // Переход через «12 часов» не должен перекидывать с конца в начало.
    if ((fraction - _scrubFraction).abs() > 0.5) {
      fraction = _scrubFraction > 0.5 ? 1.0 : 0.0;
    }
    return fraction.clamp(0.0, 1.0);
  }

  void _scrubTo(Offset local) {
    final duration = _controller.value.duration;
    if (duration == Duration.zero) return;
    _scrubFraction = _fractionAt(local);
    _controller.seekTo(duration * _scrubFraction);
    setState(() {});
  }

  void _scrubStart(Offset local) {
    _wasPlaying = _controller.value.isPlaying;
    _scrubbing = true;
    _scrubFraction = _controller.value.duration == Duration.zero
        ? 0
        : _controller.value.position.inMilliseconds /
              _controller.value.duration.inMilliseconds;
    _controller.pause();
    HapticFeedback.selectionClick();
    _scrubTo(local);
  }

  void _scrubEnd() {
    _scrubbing = false;
    // Дотянули до конца — ролик играет с начала, а не замирает на последнем кадре.
    if (_scrubFraction >= 0.995) {
      _controller.seekTo(Duration.zero);
    }
    if (_wasPlaying || _scrubFraction >= 0.995) _controller.play();
    setState(() {});
  }

  void _toggle() {
    final value = _controller.value;
    if (value.volume == 0) {
      // Немой повтор крутится на обычной скорости; выбранная — когда слушают.
      _controller
        ..setVolume(1)
        ..setLooping(false)
        ..setPlaybackSpeed(ref.read(playbackSpeedProvider))
        ..seekTo(Duration.zero)
        ..play();
    } else if (value.isPlaying) {
      _controller.pause();
    } else {
      _controller.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = _controller.value;
    final progress = value.duration.inMilliseconds == 0
        ? 0.0
        : value.position.inMilliseconds / value.duration.inMilliseconds;
    final withSound = value.volume > 0;

    return RawGestureDetector(
      gestures: {
        _RingScrubRecognizer: GestureRecognizerFactoryWithHandlers<_RingScrubRecognizer>(
          () => _RingScrubRecognizer(),
          (recognizer) {
            recognizer
              ..accepts = _onRing
              ..onStart = _scrubStart
              ..onMove = _scrubTo
              ..onEnd = _scrubEnd;
          },
        ),
        TapGestureRecognizer: GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
          () => TapGestureRecognizer(),
          (recognizer) {
            recognizer.onTap = _ready && !_scrubbing ? _toggle : null;
          },
        ),
      },
      child: SizedBox.square(
        dimension: _size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            ClipOval(
              child: SizedBox.square(
                dimension: _size,
                child: _ready
                    ? FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: value.size.width,
                          height: value.size.height,
                          child: VideoPlayer(_controller),
                        ),
                      )
                    : ColoredBox(color: AppColors.ink),
              ),
            ),
            if (withSound)
              CustomPaint(
                size: const Size.square(_size),
                painter: _RingPainter(
                  progress: (_scrubbing ? _scrubFraction : progress).clamp(0.0, 1.0),
                  color: AppColors.primaryTint,
                  track: Colors.white24,
                  knob: _scrubbing,
                ),
              ),
            if (withSound)
              Positioned(
                top: 14,
                child: SpeedChip(
                  speed: ref.watch(playbackSpeedProvider),
                  color: Colors.white,
                  background: Colors.black54,
                  onTap: () => _controller.setPlaybackSpeed(
                    ref.read(playbackSpeedProvider.notifier).next(),
                  ),
                ),
              ),
            if (_ready && (!withSound || !value.isPlaying))
              Positioned(
                bottom: 14,
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    withSound ? Icons.play_arrow : Icons.volume_off,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Кольцо прогресса кружка: тонкая дорожка и дуга от «12 часов» по часовой;
/// при перемотке на конце дуги — ползунок.
class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.color,
    required this.track,
    required this.knob,
  });

  final double progress;
  final Color color;
  final Color track;
  final bool knob;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = knob ? 5.0 : 3.0;
    final rect = (Offset.zero & size).deflate(stroke / 2 + 1);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, 2 * math.pi, false, paint..color = track);
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * progress, false, paint..color = color);
    if (knob) {
      final angle = -math.pi / 2 + 2 * math.pi * progress;
      final center = rect.center + Offset(math.cos(angle), math.sin(angle)) * (rect.width / 2);
      canvas.drawCircle(center, 9, Paint()..color = Colors.white);
      canvas.drawCircle(center, 6, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.knob != knob || old.color != color;
}

/// Забирает касание сразу, если оно началось на кольце кружка, и отдаёт
/// положение пальца: так перемотка не конфликтует со свайпом «ответить».
class _RingScrubRecognizer extends OneSequenceGestureRecognizer {
  bool Function(Offset local) accepts = (_) => false;
  void Function(Offset local)? onStart;
  void Function(Offset local)? onMove;
  VoidCallback? onEnd;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (!accepts(event.localPosition)) return;
    startTrackingPointer(event.pointer, event.transform);
    resolve(GestureDisposition.accepted);
    onStart?.call(event.localPosition);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) {
      onMove?.call(event.localPosition);
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      stopTrackingPointer(event.pointer);
      onEnd?.call();
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  String get debugDescription => 'ring scrub';
}

/// Видео в ленте как видео: рамка фиксированных пропорций (чтобы список не
/// «прыгал», пока ролик загружается), первый кадр, кнопка «play» и длительность
/// или размер. Небольшие ролики подгружаются сами (с задержкой — при быстрой
/// прокрутке не стартуем десяток декодеров), тяжёлые — по тапу. Тап открывает
/// ролик на весь экран.
class VideoPreview extends ConsumerStatefulWidget {
  const VideoPreview({
    super.key,
    required this.message,
    this.aspectRatio = 16 / 9,
    this.autoLoadMaxBytes = 8 * 1024 * 1024,
  });

  final ChatMessage message;
  final double aspectRatio;
  final int autoLoadMaxBytes;

  @override
  ConsumerState<VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends ConsumerState<VideoPreview> {
  Timer? _delay;
  VideoPlayerController? _controller;
  String? _path;
  var _loading = false;
  var _failed = false;

  @override
  void initState() {
    super.initState();
    final size = widget.message.attachment?.size ?? 0;
    if (size > 0 && size <= widget.autoLoadMaxBytes) {
      _delay = Timer(const Duration(milliseconds: 400), _load);
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  Future<String?> _load() async {
    if (_path != null) return _path;
    if (_loading) return null;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final path = await ref
          .read(chatRepositoryProvider)
          .attachmentFile(widget.message);
      if (!mounted) return null;
      _path = path;
      final controller = VideoPlayerController.file(File(path));
      await controller.initialize();
      await controller.setVolume(0);
      if (!mounted) {
        await controller.dispose();
        return path;
      }
      setState(() {
        _controller = controller;
        _loading = false;
      });
      return path;
    } catch (error) {
      AppLog.add('Видео не загрузилось: $error');
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
      return null;
    }
  }

  Future<void> _open() async {
    final path = _path ?? await _load();
    if (path == null || !mounted) return;
    await Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(builder: (_) => VideoFullScreen(filePath: path)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final attachment = widget.message.attachment!;
    final controller = _controller;
    final label = [
      if (attachment.durationMs != null)
        formatDuration(Duration(milliseconds: attachment.durationMs!))
      else if (controller != null && controller.value.isInitialized)
        formatDuration(controller.value.duration),
      formatFileSize(attachment.size),
    ].join(' · ');

    return Semantics(
      button: true,
      label: 'Видео, $label',
      child: GestureDetector(
        onTap: _open,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: AspectRatio(
            aspectRatio: widget.aspectRatio,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: AppColors.card),
                if (controller != null && controller.value.isInitialized)
                  FittedBox(
                    fit: BoxFit.cover,
                    clipBehavior: Clip.hardEdge,
                    child: SizedBox(
                      width: controller.value.size.width,
                      height: controller.value.size.height,
                      child: VideoPlayer(controller),
                    ),
                  ),
                Center(
                  child: _loading
                      ? const SizedBox(
                          width: 36,
                          height: 36,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        )
                      : Container(
                          width: 56,
                          height: 56,
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _failed ? Icons.refresh : Icons.play_arrow_rounded,
                            size: 34,
                            color: Colors.white,
                          ),
                        ),
                ),
                Positioned(
                  left: 10,
                  bottom: 8,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      child: Text(
                        _failed ? 'Не загрузилось — нажмите ещё раз' : label,
                        style: const TextStyle(fontSize: 11, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Видео на весь экран.
class VideoFullScreen extends StatefulWidget {
  const VideoFullScreen({super.key, required this.filePath});

  final String filePath;

  @override
  State<VideoFullScreen> createState() => _VideoFullScreenState();
}

class _VideoFullScreenState extends State<VideoFullScreen> {
  late final VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.filePath))
      ..addListener(() {
        if (mounted) setState(() {});
      })
      ..initialize().then((_) => _controller.play());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = _controller.value;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: value.isInitialized
            ? GestureDetector(
                onTap: () =>
                    value.isPlaying ? _controller.pause() : _controller.play(),
                child: AspectRatio(
                  aspectRatio: value.aspectRatio,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      VideoPlayer(_controller),
                      if (!value.isPlaying)
                        const Icon(
                          Icons.play_circle_fill,
                          size: 64,
                          color: Colors.white70,
                        ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: VideoProgressIndicator(
                          _controller,
                          allowScrubbing: true,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : const CircularProgressIndicator(),
      ),
    );
  }
}

// ── скорость воспроизведения ────────────────────────────────────────────────

const playbackSpeeds = [1.0, 1.25, 1.5, 1.75, 2.0, 2.5];
const _speedPrefsKey = 'chat_playback_speed';

/// Скорость голосовых и кружков — одна на всё приложение и запоминается:
/// кто слушает на 1,5×, хочет так слушать и следующее.
class PlaybackSpeed extends Notifier<double> {
  @override
  double build() {
    _restore();
    return 1.0;
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getDouble(_speedPrefsKey);
      if (saved != null && playbackSpeeds.contains(saved)) state = saved;
    } catch (_) {}
  }

  /// Следующая скорость по кругу: 1 → 1,25 → … → 2,5 → 1.
  double next() {
    final i = playbackSpeeds.indexOf(state);
    state = playbackSpeeds[(i + 1) % playbackSpeeds.length];
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setDouble(_speedPrefsKey, state))
        .catchError((_) => false);
    return state;
  }
}

final playbackSpeedProvider = NotifierProvider<PlaybackSpeed, double>(
  PlaybackSpeed.new,
);

String speedLabel(double speed) =>
    '${speed == speed.roundToDouble() ? speed.toInt() : speed.toString().replaceAll('.', ',')}×';

/// Кнопка скорости: «1,5×». Тап — следующая скорость.
class SpeedChip extends StatelessWidget {
  const SpeedChip({
    super.key,
    required this.speed,
    required this.onTap,
    required this.color,
    this.background,
  });

  final double speed;
  final VoidCallback onTap;
  final Color color;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Скорость ${speedLabel(speed)}',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          constraints: const BoxConstraints(minWidth: 40),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: background ?? color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            speedLabel(speed),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

// ── голосовые ────────────────────────────────────────────────────────────────

/// Один плеер на всё приложение: новое голосовое останавливает предыдущее.
class VoicePlayback extends ChangeNotifier {
  VoicePlayback() {
    _subscriptions
      ..add(
        _player.onPositionChanged.listen((p) {
          position = p;
          notifyListeners();
        }),
      )
      ..add(
        _player.onDurationChanged.listen((d) {
          duration = d;
          notifyListeners();
        }),
      )
      ..add(
        _player.onPlayerComplete.listen((_) {
          playingId = null;
          position = Duration.zero;
          notifyListeners();
        }),
      );
  }

  final _player = AudioPlayer();
  final _subscriptions = <StreamSubscription<Object?>>[];
  String? playingId;
  bool paused = false;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;

  Future<void> toggle(String messageId, String path, {double speed = 1}) async {
    if (playingId == messageId) {
      if (paused) {
        await _player.resume();
      } else {
        await _player.pause();
      }
      paused = !paused;
    } else {
      await _player.stop();
      playingId = messageId;
      paused = false;
      position = Duration.zero;
      duration = Duration.zero;
      await _player.play(DeviceFileSource(path));
      await setSpeed(speed);
    }
    notifyListeners();
  }

  Future<void> seek(Duration to) => _player.seek(to);

  Future<void> setSpeed(double speed) async {
    try {
      await _player.setPlaybackRate(speed);
    } catch (error) {
      AppLog.add('Скорость голосового: $error');
    }
  }

  @override
  void dispose() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }
}

final voicePlaybackProvider = ChangeNotifierProvider.autoDispose<VoicePlayback>(
  (ref) => VoicePlayback(),
);

class VoiceMessagePlayer extends ConsumerWidget {
  const VoiceMessagePlayer({
    super.key,
    required this.messageId,
    required this.filePath,
    required this.attachment,
    required this.mine,
  });

  final String messageId;
  final String filePath;
  final ChatAttachment attachment;
  final bool mine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(voicePlaybackProvider);
    final active = playback.playingId == messageId;
    final playing = active && !playback.paused;
    final total = active && playback.duration > Duration.zero
        ? playback.duration
        : Duration(milliseconds: attachment.durationMs ?? 0);
    final progress = active && total.inMilliseconds > 0
        ? (playback.position.inMilliseconds / total.inMilliseconds).clamp(
            0.0,
            1.0,
          )
        : 0.0;
    final color = mine ? AppColors.onBubbleMine : AppColors.primaryTint;
    final bars = _bars(attachment.waveform, messageId);
    final speed = ref.watch(playbackSpeedProvider);

    return SizedBox(
      width: 240,
      child: Row(
        children: [
          InkResponse(
            onTap: () => playback.toggle(messageId, filePath, speed: speed),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Тап или протяжка по волне — перемотка.
                LayoutBuilder(
                  builder: (context, constraints) {
                    void seekAt(double dx) {
                      if (!active || total == Duration.zero) return;
                      final f = (dx / constraints.maxWidth).clamp(0.0, 1.0);
                      playback.seek(total * f);
                    }

                    return GestureDetector(
                      onTapDown: (d) => seekAt(d.localPosition.dx),
                      onHorizontalDragUpdate: (d) => seekAt(d.localPosition.dx),
                      child: SizedBox(
                        height: 28,
                        child: Row(
                          children: [
                            for (var i = 0; i < bars.length; i++)
                              Expanded(
                                child: Container(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 0.8,
                                  ),
                                  height: 4 + 24 * bars[i],
                                  decoration: BoxDecoration(
                                    color: i / bars.length < progress
                                        ? color
                                        : color.withValues(alpha: 0.35),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        active
                            ? '${formatDuration(playback.position)} / ${formatDuration(total)}'
                            : formatDuration(total),
                        style: TextStyle(
                          fontSize: 11,
                          color: color.withValues(alpha: 0.75),
                        ),
                      ),
                    ),
                    SpeedChip(
                      speed: speed,
                      color: color,
                      onTap: () {
                        final next = ref
                            .read(playbackSpeedProvider.notifier)
                            .next();
                        if (active) playback.setSpeed(next);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static const _barCount = 32;

  /// Волна с сервера; у старых голосовых её нет — тогда стабильный узор по id.
  static List<double> _bars(List<double>? waveform, String seed) {
    if (waveform == null || waveform.isEmpty) {
      final hash = seed.hashCode;
      return [
        for (var i = 0; i < _barCount; i++)
          0.2 + 0.8 * (((hash * (i + 1) * 2654435761) & 0xFF) / 255),
      ];
    }
    return downsample(waveform, _barCount);
  }
}

/// Сжать ряд громкостей до [count] столбиков (максимум в каждом окне).
List<double> downsample(List<double> values, int count) {
  if (values.isEmpty) return List.filled(count, 0.1);
  if (values.length <= count) {
    return [...values, ...List.filled(count - values.length, 0.1)];
  }
  final step = values.length / count;
  return [
    for (var i = 0; i < count; i++)
      values
          .sublist(
            (i * step).floor(),
            ((i + 1) * step).floor().clamp(0, values.length),
          )
          .fold<double>(0, (a, b) => a > b ? a : b),
  ];
}

String formatDuration(Duration d) =>
    '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

String formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes Б';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} КБ';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} МБ';
}

IconData iconForMime(String? mime) {
  if (mime == null) return Icons.insert_drive_file_outlined;
  if (mime.startsWith('image/')) return Icons.image_outlined;
  if (mime.startsWith('video/')) return Icons.movie_outlined;
  if (mime.startsWith('audio/')) return Icons.audiotrack_outlined;
  if (mime.contains('pdf')) return Icons.picture_as_pdf_outlined;
  if (mime.contains('zip') || mime.contains('rar') || mime.contains('7z')) {
    return Icons.folder_zip_outlined;
  }
  if (mime.contains('sheet') || mime.contains('excel')) {
    return Icons.table_chart_outlined;
  }
  if (mime.contains('word') || mime.contains('text')) {
    return Icons.description_outlined;
  }
  return Icons.insert_drive_file_outlined;
}
