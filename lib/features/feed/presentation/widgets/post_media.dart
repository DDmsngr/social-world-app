import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/debug/app_log.dart';
import '../../../../core/media/media_kind.dart';
import '../../../../core/media/photo_viewer.dart';
import '../../../../core/media/playback_focus.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../../core/theme/app_colors.dart';

/// Вложения поста: одна фотография, лента из нескольких или видео.
///
/// Рамка — в пропорциях первого файла, как в привычных фотосетях: от 4:5
/// (портрет) до 1.91:1 (панорама), поэтому кадр почти не обрезается. Пока
/// пропорции неизвестны — 1:1; узнанные запоминаются, и при прокрутке назад
/// карточка не прыгает по высоте.
class PostMedia extends StatefulWidget {
  const PostMedia({super.key, required this.urls});

  final List<String> urls;

  @override
  State<PostMedia> createState() => _PostMediaState();
}

const _minRatio = 4 / 5;
const _maxRatio = 1.91;

final _ratios = <String, double>{};

class _PostMediaState extends State<PostMedia> {
  final _pageController = PageController();
  var _page = 0;
  ImageStream? _stream;
  ImageStreamListener? _listener;

  String get _first => widget.urls.first;

  @override
  void initState() {
    super.initState();
    _measure();
  }

  @override
  void didUpdateWidget(PostMedia old) {
    super.didUpdateWidget(old);
    if (old.urls.isEmpty || widget.urls.isEmpty || old.urls.first != _first) {
      _stopMeasure();
      _measure();
    }
  }

  void _measure() {
    if (widget.urls.isEmpty || _ratios.containsKey(_first) || isVideoUrl(_first)) return;
    final provider = _first.startsWith('http')
        ? CachedNetworkImageProvider(_first)
        : imageProviderFor(_first);
    final stream = provider.resolve(ImageConfiguration.empty);
    final listener = ImageStreamListener((info, _) {
      _setRatio(_first, info.image.width / info.image.height);
      _stopMeasure();
    }, onError: (_, _) => _stopMeasure());
    stream.addListener(listener);
    _stream = stream;
    _listener = listener;
  }

  void _stopMeasure() {
    final listener = _listener;
    if (listener != null) _stream?.removeListener(listener);
    _stream = null;
    _listener = null;
  }

  void _setRatio(String url, double ratio) {
    if (!ratio.isFinite || ratio <= 0) return;
    _ratios[url] = ratio.clamp(_minRatio, _maxRatio);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _stopMeasure();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.urls.isEmpty) return const SizedBox.shrink();
    final ratio = _ratios[_first] ?? 1.0;

    if (widget.urls.length == 1) {
      return AspectRatio(
        aspectRatio: ratio,
        child: _MediaItem(
          url: _first,
          allUrls: widget.urls,
          onVideoRatio: (r) => _setRatio(_first, r),
        ),
      );
    }

    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        AspectRatio(
          aspectRatio: ratio,
          child: PageView.builder(
            controller: _pageController,
            itemCount: widget.urls.length,
            onPageChanged: (page) => setState(() => _page = page),
            itemBuilder: (_, index) => _MediaItem(
              url: widget.urls[index],
              allUrls: widget.urls,
              onVideoRatio: index == 0 ? (r) => _setRatio(_first, r) : null,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var index = 0; index < widget.urls.length; index++)
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: index == _page
                        ? AppColors.paper
                        : AppColors.paper.withValues(alpha: 0.4),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MediaItem extends StatelessWidget {
  const _MediaItem({required this.url, required this.allUrls, this.onVideoRatio});

  final String url;
  final List<String> allUrls;
  final ValueChanged<double>? onVideoRatio;

  /// Тап по фото открывает его на весь экран; листать можно все фото поста.
  void _open(BuildContext context) {
    final photos = allUrls.where((item) => !isVideoUrl(item)).toList();
    showPhotoViewer(
      context,
      urls: photos,
      initialIndex: photos.indexOf(url).clamp(0, photos.length - 1),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isVideoUrl(url)) return _VideoItem(url: url, onRatio: onVideoRatio);

    return GestureDetector(
      onTap: () => _open(context),
      behavior: HitTestBehavior.opaque,
      child: _image(),
    );
  }

  Widget _image() {
    // В режиме заглушек ссылкой служит сам файл (на вебе это blob:), кеш для
    // такого не нужен и не работает.
    if (!url.startsWith('http')) {
      return Image(
        image: imageProviderFor(url),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => ColoredBox(color: AppColors.ink2),
      );
    }

    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      placeholder: (_, _) => ColoredBox(color: AppColors.ink2),
      errorWidget: (_, _, _) => ColoredBox(
        color: AppColors.ink2,
        child: Center(
          child: Icon(
            Icons.image_not_supported_outlined,
            color: AppColors.textFaint,
          ),
        ),
      ),
    );
  }
}

class _VideoItem extends StatefulWidget {
  const _VideoItem({required this.url, this.onRatio});

  final String url;
  final ValueChanged<double>? onRatio;

  @override
  State<_VideoItem> createState() => _VideoItemState();
}

class _VideoItemState extends State<_VideoItem> {
  late final VideoPlayerController _controller;
  var _ready = false;
  var _failed = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      // Пауза может прийти извне (запустили другое видео) — перерисоваться.
      ..addListener(_onChange)
      ..setLooping(true)
      ..initialize().then((_) {
        widget.onRatio?.call(_controller.value.aspectRatio);
        if (mounted) setState(() => _ready = true);
      }).catchError((Object error) {
        // Битая ссылка или неподдерживаемый кодек. Раньше здесь оставался
        // вечный кружок загрузки, и видео выглядело как «сейчас докрутится».
        AppLog.add('Видео не открылось: $error');
        if (mounted) setState(() => _failed = true);
      });
  }

  var _wasPlaying = false;

  void _onChange() {
    final playing = _controller.value.isPlaying;
    if (playing != _wasPlaying && mounted) setState(() => _wasPlaying = playing);
  }

  @override
  void dispose() {
    PlaybackFocus.release(_controller);
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    if (_controller.value.isPlaying) {
      _controller.pause();
    } else {
      PlaybackFocus.claim(_controller);
      _controller.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return ColoredBox(
        color: AppColors.ink2,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.videocam_off_outlined, color: AppColors.textFaint),
              const SizedBox(height: 6),
              Text(
                'Видео не открылось',
                style: TextStyle(color: AppColors.textFaint, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    if (!_ready) {
      return ColoredBox(
        color: AppColors.ink2,
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: _toggle,
      child: Stack(
        fit: StackFit.expand,
        children: [
          FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: _controller.value.size.width,
              height: _controller.value.size.height,
              child: VideoPlayer(_controller),
            ),
          ),
          if (!_controller.value.isPlaying)
            Center(
              child: CircleAvatar(
                radius: 26,
                backgroundColor: AppColors.ink.withAlpha(0x99),
                child: Icon(Icons.play_arrow, color: AppColors.paper, size: 30),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: VideoProgressIndicator(
              _controller,
              allowScrubbing: true,
              colors: VideoProgressColors(
                playedColor: AppColors.primaryTint,
                bufferedColor: AppColors.hairStrong,
                backgroundColor: AppColors.hair,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
