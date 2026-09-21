import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/user_avatar.dart';

/// Полноэкранный просмотр фотографий: листание, масштаб щипком и двойным
/// тапом, закрытие крестиком, системным «назад» или свайпом вниз.
Future<void> showPhotoViewer(
  BuildContext context, {
  required List<String> urls,
  int initialIndex = 0,
  String? caption,
  List<String?>? captions,
}) {
  if (urls.isEmpty) return Future.value();
  return Navigator.of(context, rootNavigator: true).push<void>(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 180),
      reverseTransitionDuration: const Duration(milliseconds: 140),
      pageBuilder: (_, _, _) => PhotoViewer(
        urls: urls,
        initialIndex: initialIndex.clamp(0, urls.length - 1),
        caption: caption,
        captions: captions,
      ),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

class PhotoViewer extends StatefulWidget {
  const PhotoViewer({
    super.key,
    required this.urls,
    this.initialIndex = 0,
    this.caption,
    this.captions,
  });

  final List<String> urls;
  final int initialIndex;

  /// Подпись для всех страниц сразу; [captions] — своя на каждую.
  final String? caption;
  final List<String?>? captions;

  @override
  State<PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<PhotoViewer> {
  late final PageController _pages = PageController(
    initialPage: widget.initialIndex,
  );
  late int _index = widget.initialIndex;
  var _zoomed = false;
  double _dragOffset = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _close() => Navigator.of(context).maybePop();

  String? get _caption {
    final list = widget.captions;
    if (list != null && _index < list.length) return list[_index];
    return widget.caption;
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
      ),
      child: Scaffold(
        backgroundColor: Colors.black.withValues(
          alpha: (1 - _dragOffset.abs() / 400).clamp(0.4, 1.0),
        ),
        body: GestureDetector(
          // Свайп вниз закрывает, пока фото не приближено: иначе он же
          // конфликтовал бы с перемещением увеличенной картинки.
          onVerticalDragUpdate: _zoomed
              ? null
              : (details) => setState(() => _dragOffset += details.delta.dy),
          onVerticalDragEnd: _zoomed
              ? null
              : (details) {
                  if (_dragOffset.abs() > 120 ||
                      (details.primaryVelocity ?? 0).abs() > 900) {
                    _close();
                  } else {
                    setState(() => _dragOffset = 0);
                  }
                },
          child: Stack(
            fit: StackFit.expand,
            children: [
              Transform.translate(
                offset: Offset(0, _dragOffset),
                child: PageView.builder(
                  controller: _pages,
                  physics: _zoomed
                      ? const NeverScrollableScrollPhysics()
                      : const PageScrollPhysics(),
                  itemCount: widget.urls.length,
                  onPageChanged: (page) => setState(() => _index = page),
                  itemBuilder: (_, page) => _ZoomablePhoto(
                    url: widget.urls[page],
                    onZoomChanged: (zoomed) {
                      if (_zoomed != zoomed) setState(() => _zoomed = zoomed);
                    },
                  ),
                ),
              ),
              Positioned(
                top: media.padding.top + 8,
                right: 12,
                child: Material(
                  color: Colors.black54,
                  shape: const CircleBorder(),
                  child: IconButton(
                    onPressed: _close,
                    tooltip: 'Закрыть',
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ),
              ),
              if (widget.urls.length > 1)
                Positioned(
                  top: media.padding.top + 20,
                  left: 20,
                  child: Text(
                    '${_index + 1} / ${widget.urls.length}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
              if (_caption case final caption? when caption.isNotEmpty)
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: media.padding.bottom + 20,
                  child: Text(
                    caption,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ZoomablePhoto extends StatefulWidget {
  const _ZoomablePhoto({required this.url, required this.onZoomChanged});

  final String url;
  final ValueChanged<bool> onZoomChanged;

  @override
  State<_ZoomablePhoto> createState() => _ZoomablePhotoState();
}

class _ZoomablePhotoState extends State<_ZoomablePhoto> {
  final _controller = TransformationController();
  TapDownDetails? _doubleTap;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      widget.onZoomChanged(_controller.value.getMaxScaleOnAxis() > 1.02);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggleZoom() {
    if (_controller.value.getMaxScaleOnAxis() > 1.02) {
      _controller.value = Matrix4.identity();
      return;
    }
    final point = _doubleTap?.localPosition ?? Offset.zero;
    _controller.value = Matrix4.identity()
      ..translateByDouble(-point.dx * 1.5, -point.dy * 1.5, 0, 1)
      ..scaleByDouble(2.5, 2.5, 1, 1);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTapDown: (details) => _doubleTap = details,
      onDoubleTap: _toggleZoom,
      child: InteractiveViewer(
        transformationController: _controller,
        minScale: 1,
        maxScale: 5,
        child: Center(
          child: Image(
            image: imageProviderFor(widget.url),
            fit: BoxFit.contain,
            loadingBuilder: (context, child, progress) => progress == null
                ? child
                : const Center(
                    child: CircularProgressIndicator(color: Colors.white54),
                  ),
            errorBuilder: (_, _, _) => const Center(
              child: Icon(
                Icons.image_not_supported_outlined,
                color: Colors.white54,
                size: 40,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
