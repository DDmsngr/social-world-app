import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../debug/app_log.dart';
import '../theme/app_colors.dart';

/// Видеоаватар: короткий беззвучный ролик по кругу в кружке. Пока ролик не
/// загрузился (или не удалось) — [fallback], обычное фото, так что аватар
/// никогда не остаётся пустым.
class VideoAvatar extends StatefulWidget {
  const VideoAvatar({
    super.key,
    required this.url,
    required this.radius,
    required this.fallback,
  });

  final String url;
  final double radius;
  final Widget fallback;

  @override
  State<VideoAvatar> createState() => _VideoAvatarState();
}

class _VideoAvatarState extends State<VideoAvatar> {
  VideoPlayerController? _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.url),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _controller = controller;
    controller.initialize().then((_) {
      controller
        ..setLooping(true)
        ..setVolume(0)
        ..play();
      if (mounted) setState(() => _ready = true);
    }).catchError((Object error) {
      AppLog.add('Видеоаватар не загрузился: $error');
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final size = widget.radius * 2;
    if (!_ready || controller == null) return widget.fallback;
    return SizedBox.square(
      dimension: size,
      child: ClipOval(
        child: ColoredBox(
          color: AppColors.ink2,
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: controller.value.size.width,
              height: controller.value.size.height,
              child: VideoPlayer(controller),
            ),
          ),
        ),
      ),
    );
  }
}
