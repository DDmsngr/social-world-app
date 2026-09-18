import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/media/media_kind.dart';
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
        child: _MediaItem(url: widget.urls.first),
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
            itemBuilder: (_, index) => _MediaItem(url: widget.urls[index]),
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
  const _MediaItem({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    if (isVideoUrl(url)) return _VideoItem(url: url);

    // В режиме заглушек ссылкой служит сам файл (на вебе это blob:), кеш для
    // такого не нужен и не работает.
    if (!url.startsWith('http')) {
      return Image.network(
        url,
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

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..setLooping(true)
      ..initialize().then((_) {
        if (mounted) setState(() => _ready = true);
      }).catchError((_) {
        // Битая ссылка или неподдерживаемый кодек — карточка просто останется
        // с заглушкой вместо кадра, ронять ленту из-за этого незачем.
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
                backgroundColor: Color(0x99151417),
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
