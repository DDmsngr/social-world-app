import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/debug/app_log.dart';
import '../../../../core/theme/app_colors.dart';

/// Достаточно ли длинный и пологий протяг вправо, чтобы считать его выходом.
/// Вынесено отдельно, чтобы проверяться тестом без экрана.
bool isBackSwipe({
  required double dx,
  required double dy,
  required Duration elapsed,
}) {
  if (dx < 130) return false;
  // Почти горизонтальный: вертикальная прокрутка ленты сюда не попадает.
  if (dy.abs() > dx * 0.55) return false;
  // Намеренный жест, а не медленное водомерное перетаскивание.
  return elapsed < const Duration(milliseconds: 900);
}

/// Свайп слева направо по переписке закрывает её, как кнопка «Назад». Работает
/// на сырых событиях касания (Listener), а не через жесты: иначе спорил бы со
/// свайпом сообщения влево (ответ) и с прокруткой. Подсказка про жест
/// показывается всего несколько раз и тихо исчезает.
class SwipeBackToExit extends StatefulWidget {
  const SwipeBackToExit({super.key, required this.onExit, required this.child});

  final VoidCallback onExit;
  final Widget child;

  @override
  State<SwipeBackToExit> createState() => _SwipeBackToExitState();
}

class _SwipeBackToExitState extends State<SwipeBackToExit> {
  static const _hintKey = 'swipe_back_hint_count';
  static const _hintTimes = 3;

  Offset? _start;
  DateTime _startedAt = DateTime(0);
  int? _pointer;
  var _hint = false;
  Timer? _hintTimer;

  @override
  void initState() {
    super.initState();
    _maybeShowHint();
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    super.dispose();
  }

  Future<void> _maybeShowHint() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final shown = prefs.getInt(_hintKey) ?? 0;
      if (shown >= _hintTimes) return;
      await prefs.setInt(_hintKey, shown + 1);
      await Future<void>.delayed(const Duration(milliseconds: 1400));
      if (!mounted) return;
      setState(() => _hint = true);
      _hintTimer = Timer(const Duration(milliseconds: 3200), () {
        if (mounted) setState(() => _hint = false);
      });
    } catch (error) {
      AppLog.add('Подсказка свайпа: $error');
    }
  }

  /// Жест освоен — подсказка больше не нужна.
  Future<void> _learned() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_hintKey, _hintTimes);
    } catch (_) {}
  }

  void _down(PointerDownEvent event) {
    // Только первый палец: щипок двумя пальцами жестом выхода не считается.
    if (_pointer != null) {
      _start = null;
      return;
    }
    _pointer = event.pointer;
    _start = event.position;
    _startedAt = DateTime.now();
  }

  void _up(PointerEvent event) {
    if (event.pointer != _pointer) return;
    final start = _start;
    _pointer = null;
    _start = null;
    if (start == null || event is PointerCancelEvent) return;
    final delta = event.position - start;
    if (isBackSwipe(dx: delta.dx, dy: delta.dy, elapsed: DateTime.now().difference(_startedAt))) {
      HapticFeedback.lightImpact();
      setState(() => _hint = false);
      unawaited(_learned());
      widget.onExit();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _down,
      onPointerUp: _up,
      onPointerCancel: _up,
      child: Stack(
        children: [
          Positioned.fill(child: widget.child),
          Positioned(
            left: 0,
            right: 0,
            bottom: 16,
            child: IgnorePointer(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 500),
                opacity: _hint ? 0.62 : 0,
                child: Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.ink.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: AppColors.hair),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.swipe_right_alt, size: 18, color: AppColors.textDim),
                          const SizedBox(width: 8),
                          Text(
                            'Свайп вправо — выход',
                            style: TextStyle(fontSize: 13, color: AppColors.textDim),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
