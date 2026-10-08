import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Ветка карты (Pulse): нативная карта, её не затеняем и не двигаем, иначе
/// платформенный слой моргает. Она переключается мгновенно и устроена как в
/// обычном IndexedStack: без прозрачности и сдвига.
const mapBranchIndex = 1;

/// Контейнер вкладок с плавным переходом для go_router.
Widget animatedBranchContainer(
  BuildContext context,
  StatefulNavigationShell navigationShell,
  List<Widget> children,
) {
  return AnimatedBranches(
    currentIndex: navigationShell.currentIndex,
    children: children,
  );
}

/// Вкладки: новая мягко проявляется и чуть выезжает снизу, старая тает. Все
/// ветки живут разом, как в IndexedStack, поэтому состояние вкладок (прокрутка,
/// карта, играющее видео) не теряется.
///
/// Важно: у каждой ветки дерево обёрток постоянное, оно не меняется между
/// «видна», «скрыта» и «в переходе». Раньше обёртки добавлялись и убирались по
/// ходу анимации, и Flutter пересоздавал нижележащие виджеты, в том числе
/// карту, — она переставала реагировать.
class AnimatedBranches extends StatelessWidget {
  const AnimatedBranches({
    super.key,
    required this.currentIndex,
    required this.children,
    this.instantIndex = mapBranchIndex,
  });

  final int currentIndex;
  final List<Widget> children;

  /// Ветка без анимации (карта).
  final int instantIndex;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < children.length; i++)
          _Branch(
            key: ValueKey('branch-$i'),
            active: i == currentIndex,
            animated: i != instantIndex,
            child: children[i],
          ),
      ],
    );
  }
}

class _Branch extends StatefulWidget {
  const _Branch({super.key, required this.active, required this.animated, required this.child});

  final bool active;
  final bool animated;
  final Widget child;

  @override
  State<_Branch> createState() => _BranchState();
}

class _BranchState extends State<_Branch> with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 240);

  // Создаётся сразу, а не лениво: у ветки карты в build он не нужен, и при
  // закрытии экрана ленивое создание падало бы внутри dispose.
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _duration,
      value: widget.active ? 1 : 0,
    );
  }

  @override
  void didUpdateWidget(_Branch old) {
    super.didUpdateWidget(old);
    if (old.active == widget.active) return;
    if (!widget.animated) {
      _controller.value = widget.active ? 1 : 0;
    } else if (widget.active) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.animated) {
      // Без эффектов, но с теми же Offstage и TickerMode, что у IndexedStack.
      return Offstage(
        offstage: !widget.active,
        child: TickerMode(enabled: widget.active, child: widget.child),
      );
    }
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final v = Curves.easeOut.transform(_controller.value);
        // Скрыта совсем: не рисуется и не тикает, но состояние держит.
        final hidden = _controller.value == 0 && !widget.active;
        return Offstage(
          offstage: hidden,
          child: TickerMode(
            enabled: !hidden,
            child: IgnorePointer(
              ignoring: !widget.active,
              child: Opacity(
                opacity: v,
                child: Transform.translate(offset: Offset(0, (1 - v) * 14), child: child),
              ),
            ),
          ),
        );
      },
    );
  }
}
