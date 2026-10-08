import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Ветка карты (Pulse): нативная карта, её не затеняем и не двигаем, иначе
/// платформенный слой моргает. Переход на неё и с неё мгновенный.
const _mapBranch = 1;

/// Контейнер вкладок с плавным переходом: новая вкладка мягко проявляется и
/// чуть выезжает снизу, старая тает. Все ветки по-прежнему живут разом, как в
/// IndexedStack, поэтому состояние вкладок (прокрутка, карта) не теряется.
Widget animatedBranchContainer(
  BuildContext context,
  StatefulNavigationShell navigationShell,
  List<Widget> children,
) {
  return Stack(
    fit: StackFit.expand,
    children: [
      for (var i = 0; i < children.length; i++)
        _Branch(
          key: ValueKey('branch-$i'),
          active: i == navigationShell.currentIndex,
          instant: i == _mapBranch,
          child: children[i],
        ),
    ],
  );
}

class _Branch extends StatefulWidget {
  const _Branch({super.key, required this.active, required this.instant, required this.child});

  final bool active;
  final bool instant;
  final Widget child;

  @override
  State<_Branch> createState() => _BranchState();
}

class _BranchState extends State<_Branch> with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 240);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _duration,
    value: widget.active ? 1 : 0,
  );

  @override
  void didUpdateWidget(_Branch old) {
    super.didUpdateWidget(old);
    if (old.active == widget.active) return;
    // Соседняя вкладка карты: без анимации, ни её, ни те, что рядом, не
    // мерцают платформенным слоем.
    if (widget.instant) {
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
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final v = Curves.easeOut.transform(_controller.value);
        // Совсем скрытая вкладка не рисуется и не тикает, но состояние держит.
        if (_controller.value == 0 && !widget.active) {
          return Offstage(child: TickerMode(enabled: false, child: child!));
        }
        if (_controller.value == 1) return child!;
        return IgnorePointer(
          ignoring: !widget.active,
          child: Opacity(
            opacity: v,
            child: Transform.translate(offset: Offset(0, (1 - v) * 14), child: child),
          ),
        );
      },
    );
  }
}
