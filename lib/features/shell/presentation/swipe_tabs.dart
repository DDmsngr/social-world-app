import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Порядок вкладок для свайпа (индексы веток роутера): Flow, Создать, Чаты,
/// Профиль. Карта (Pulse, индекс 1) сюда не входит: на ней жесты нужны самой
/// карте, поэтому свайпом на карту не попасть и с неё не уйти — только
/// нижней панелью.
const swipeTabOrder = [0, 2, 3, 4];

/// Куда ведёт свайп с вкладки [current] в сторону [forward] (палец влево —
/// вперёд). null — дальше некуда или вкладка не участвует.
int? swipeTarget(int current, {required bool forward}) {
  final at = swipeTabOrder.indexOf(current);
  if (at < 0) return null;
  final to = at + (forward ? 1 : -1);
  if (to < 0 || to >= swipeTabOrder.length) return null;
  return swipeTabOrder[to];
}

/// Горизонтальный свайп по экрану переключает вкладки. Внутренние
/// горизонтальные прокрутки (карусели фото, лента историй, вкладки чатов)
/// выигрывают у этого жеста сами, а когда они дошли до края, их перелёт
/// передаётся сюда через [SwipeTabsHandoff].
class SwipeBetweenTabs extends StatefulWidget {
  const SwipeBetweenTabs({
    super.key,
    required this.shell,
    required this.enabled,
    required this.child,
  });

  final StatefulNavigationShell shell;

  /// Выключено в переписке, при открытой клавиатуре и т. п.
  final bool enabled;
  final Widget child;

  @override
  State<SwipeBetweenTabs> createState() => _SwipeBetweenTabsState();
}

class _SwipeBetweenTabsState extends State<SwipeBetweenTabs> {
  var _dragged = 0.0;

  /// Достаточно длинного протягивания (с заметной скоростью) либо короткого
  /// резкого броска.
  static const _farDistance = 70.0;
  static const _farVelocity = 200.0;
  static const _flickDistance = 30.0;
  static const _flickVelocity = 800.0;

  void _go({required bool forward}) {
    final target = swipeTarget(widget.shell.currentIndex, forward: forward);
    if (target != null) widget.shell.goBranch(target);
  }

  @override
  Widget build(BuildContext context) {
    // Вкладка вне порядка свайпа (карта) или жест выключен: распознавателей
    // нет совсем. С пустыми обработчиками (раньше стояла проверка внутри) они
    // всё равно вступали в борьбу за касания и ломали движение карты.
    final active = widget.enabled &&
        (swipeTarget(widget.shell.currentIndex, forward: true) != null ||
            swipeTarget(widget.shell.currentIndex, forward: false) != null);
    return SwipeTabsHandoff(
      onEdge: ({required bool forward}) {
        if (widget.enabled) _go(forward: forward);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: active ? (_) => _dragged = 0 : null,
        onHorizontalDragUpdate: active ? (details) => _dragged += details.delta.dx : null,
        onHorizontalDragEnd: active
            ? (details) {
                final speed = (details.primaryVelocity ?? 0).abs();
                final distance = _dragged.abs();
                final far = distance >= _farDistance && speed >= _farVelocity;
                final flick = distance >= _flickDistance && speed >= _flickVelocity;
                if (!far && !flick) return;
                // Палец влево (отрицательное смещение) — следующая вкладка.
                _go(forward: _dragged < 0);
              }
            : null,
        child: widget.child,
      ),
    );
  }
}

/// Мост от внутренней горизонтальной прокрутки к переключению вкладок: экран,
/// у которого есть свои горизонтальные страницы, сообщает через
/// [SwipeTabsHandoff.notify], что человек тянет дальше крайней страницы.
class SwipeTabsHandoff extends StatelessWidget {
  const SwipeTabsHandoff({super.key, required this.onEdge, required this.child});

  final void Function({required bool forward}) onEdge;
  final Widget child;

  static void notify(BuildContext context, {required bool forward}) {
    context.findAncestorWidgetOfExactType<SwipeTabsHandoff>()?.onEdge(forward: forward);
  }

  @override
  Widget build(BuildContext context) => child;
}
