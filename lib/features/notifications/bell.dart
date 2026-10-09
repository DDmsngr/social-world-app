import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/audio/bell_sound.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';

/// Счётчик «пришло уведомление, пока приложение открыто». Колокольчик
/// слушает его и сам решает, показаться или потрястись.
class BellController extends Notifier<int> {
  @override
  int build() {
    ref.keepAlive();
    return 0;
  }

  void ping() => state++;
}

final bellProvider = NotifierProvider<BellController, int>(BellController.new);

/// Ненавязчивый колокольчик поверх любого экрана: появляется со звуком, когда
/// приходит уведомление, на следующие трясётся влево-вправо с тем же звуком,
/// через несколько секунд тихо уходит. Тап открывает уведомления. Постоянного
/// значка нет совсем.
class NotificationBell extends ConsumerStatefulWidget {
  const NotificationBell({super.key, required this.router});

  /// Роутер приходит снаружи: колокольчик стоит над навигатором, и
  /// `GoRouter.of(context)` здесь ещё не виден.
  final GoRouter router;

  static const stay = Duration(seconds: 6);

  @override
  ConsumerState<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends ConsumerState<NotificationBell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );
  Timer? _hide;
  var _visible = false;

  @override
  void dispose() {
    _hide?.cancel();
    _shake.dispose();
    super.dispose();
  }

  bool get _onNotificationsScreen =>
      widget.router.routeInformationProvider.value.uri.path == Routes.notifications;

  void _onPing() {
    // Список уведомлений и так перед глазами.
    if (_onNotificationsScreen) return;
    unawaited(BellSound.play());
    if (!_visible) {
      setState(() => _visible = true);
    } else {
      _shake.forward(from: 0);
    }
    _hide?.cancel();
    _hide = Timer(NotificationBell.stay, () {
      if (mounted) setState(() => _visible = false);
    });
  }

  void _open() {
    _hide?.cancel();
    setState(() => _visible = false);
    widget.router.push(Routes.notifications);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(bellProvider, (previous, next) {
      if (previous != next) _onPing();
    });

    final top = MediaQuery.paddingOf(context).top + 8;
    return Positioned(
      top: top,
      right: 12,
      child: IgnorePointer(
        ignoring: !_visible,
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutBack,
          offset: _visible ? Offset.zero : const Offset(0, -2.2),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: _visible ? 1 : 0,
            child: AnimatedBuilder(
              animation: _shake,
              builder: (context, child) {
                // Три качка с затуханием: влево-вправо и успокоилась.
                final t = _shake.value;
                final angle = math.sin(t * math.pi * 6) * 0.42 * (1 - t);
                return Transform.rotate(
                  angle: angle,
                  alignment: Alignment.topCenter,
                  child: child,
                );
              },
              child: Material(
                color: AppColors.primary,
                elevation: 4,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _open,
                  child: Padding(
                    padding: const EdgeInsets.all(11),
                    child: Icon(Icons.notifications_active, size: 24, color: AppColors.onPrimary),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
