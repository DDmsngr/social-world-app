import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../theme/app_colors.dart';

/// Расширения, по которым ссылка в `![](…)` считается видео, а не картинкой.
const _videoExtensions = {'.mp4', '.mov', '.m4v', '.webm', '.3gp', '.mkv'};

bool isVideoUrl(String url) {
  final path = Uri.tryParse(url)?.path.toLowerCase() ?? url.toLowerCase();
  return _videoExtensions.any(path.endsWith);
}

/// Видео внутри текста статьи: пока не нажали — тёмная рамка 16:9 со значком
/// «играть» (ничего не качается), по нажатию грузится и играет; нажатие во
/// время показа ставит на паузу.
class InlineVideo extends StatefulWidget {
  const InlineVideo({super.key, required this.url});

  final String url;

  @override
  State<InlineVideo> createState() => _InlineVideoState();
}

class _InlineVideoState extends State<InlineVideo> {
  VideoPlayerController? _controller;
  var _failed = false;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    setState(() => _controller = controller);
    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.play();
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final ready = controller != null && controller.value.isInitialized;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(
          aspectRatio: ready ? controller.value.aspectRatio : 16 / 9,
          child: GestureDetector(
            onTap: () {
              if (_failed) {
                setState(() {
                  _failed = false;
                  _controller?.dispose();
                  _controller = null;
                });
              } else if (controller == null) {
                _start();
              } else if (ready) {
                setState(() {
                  controller.value.isPlaying ? controller.pause() : controller.play();
                });
              }
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: AppColors.ink2),
                if (ready) VideoPlayer(controller),
                if (_failed)
                  Center(
                    child: Icon(Icons.refresh, color: AppColors.textFaint, size: 36),
                  )
                else if (controller != null && !ready)
                  const Center(child: CircularProgressIndicator(strokeWidth: 2))
                else if (!ready || !controller.value.isPlaying)
                  Center(
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: const BoxDecoration(
                        color: Color(0x99000000),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.play_arrow, color: Colors.white, size: 34),
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
