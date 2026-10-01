import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';

/// Свайп сообщения справа налево — «ответить». Сообщение едет за пальцем, из-за
/// него проступает значок; отпустили дальше порога — срабатывает [onReply] и
/// сообщение пружинит на место. Вертикальную прокрутку ленты не трогает.
class SwipeToReply extends StatefulWidget {
  const SwipeToReply({
    super.key,
    required this.child,
    required this.onReply,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback onReply;
  final bool enabled;

  /// На сколько можно утянуть сообщение и с какого места свайп засчитывается.
  static const maxDrag = 72.0;
  static const threshold = 56.0;

  @override
  State<SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<SwipeToReply> {
  double _dx = 0;
  bool _dragging = false;
  bool _armed = false;

  void _update(DragUpdateDetails details) {
    // Влево — отрицательные значения; вправо сообщение не тянется вообще.
    final next = (_dx + details.delta.dx).clamp(-SwipeToReply.maxDrag, 0.0);
    final armed = next <= -SwipeToReply.threshold;
    if (armed && !_armed) HapticFeedback.lightImpact();
    setState(() {
      _dx = next;
      _dragging = true;
      _armed = armed;
    });
  }

  void _end([DragEndDetails? details]) {
    if (_armed) widget.onReply();
    setState(() {
      _dx = 0;
      _dragging = false;
      _armed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    final progress = (-_dx / SwipeToReply.threshold).clamp(0.0, 1.0);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: _update,
      onHorizontalDragEnd: _end,
      onHorizontalDragCancel: _end,
      // passthrough: сообщение получает ширину ленты и само выравнивается
      // влево или вправо; с loose оно сжалось бы и «уехало» к краю.
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          Positioned(
            right: 12,
            top: 0,
            bottom: 0,
            child: Center(
              child: Opacity(
                opacity: progress,
                child: Transform.scale(
                  scale: 0.6 + 0.4 * progress,
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: _armed ? AppColors.primaryTint : AppColors.hair,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.reply_rounded,
                      size: 20,
                      color: _armed ? AppColors.ink : AppColors.textDim,
                    ),
                  ),
                ),
              ),
            ),
          ),
          TweenAnimationBuilder<double>(
            tween: Tween(end: _dx),
            duration: _dragging ? Duration.zero : const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            builder: (context, dx, child) =>
                Transform.translate(offset: Offset(dx, 0), child: child),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}
