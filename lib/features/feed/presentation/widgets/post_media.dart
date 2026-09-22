import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/debug/app_log.dart';
import '../../../../core/media/media_kind.dart';
import '../../../../core/media/photo_viewer.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../../core/theme/app_colors.dart';

/// Вложения поста: одна фотография, лента из нескольких или видео.
///
/// Соотношение сторон зафиксировано, чтобы карточки в ленте не прыгали по
/// высоте, пока картинки подгружаются.
class PostMedia extends StatefulWidget {
  const PostMedia({super.key, required this.urls});

  final List<String> urls;

  @override
  State<PostMedia> createState() => _PostMediaState();
}

class _PostMediaState extends State<PostMedia> {
  final _pageController = PageController();
  var _page = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.urls.isEmpty) return const SizedBox.shrink();

    if (widget.urls.length == 1) {
      return AspectRatio(
        aspectRatio: 4 / 3,
        child: _MediaItem(url: widget.urls.first, allUrls: widget.urls),
      );
    }

    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        AspectRatio(
          aspectRatio: 4 / 3,
          child: PageView.builder(
            controller: _pageController,
            itemCount: widget.urls.length,
            onPageChanged: (page) => setState(() => _page = page),
            itemBuilder: (_, index) =>
                _MediaItem(url: widget.urls[index], allUrls: widget.urls),
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
  const _MediaItem({required this.url, required this.allUrls});

  final String url;
  final List<String> allUrls;

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
    if (isVideoUrl(url)) return _VideoItem(url: url);

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
  const _VideoItem({required this.url});

  final String url;

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
      ..setLooping(true)
      ..initialize().then((_) {
        if (mounted) setState(() => _ready = true);
      }).catchError((Object error) {
        // Битая ссылка или неподдерживаемый кодек. Раньше здесь оставался
        // вечный кружок загрузки, и видео выглядело как «сейчас докрутится».
        AppLog.add('Видео не открылось: $error');
        if (mounted) setState(() => _failed = true);
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _controller.value.isPlaying ? _controller.pause() : _controller.play();
    });
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
