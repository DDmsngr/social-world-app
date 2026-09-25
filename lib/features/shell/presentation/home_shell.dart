import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/update/update_controller.dart';
import '../../../core/update/update_dot.dart';
import '../../notifications/notifications.dart';
import '../../profile/presentation/providers/profile_providers.dart';
import '../../saved/saved.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell>
    with WidgetsBindingObserver {
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Одна проверка за запуск: оболочка создаётся после входа и живёт до
    // закрытия приложения, так что дёргать сеть чаще незачем.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(updateControllerProvider.notifier).check();
      // Заранее поднимаем то, что нужно карточкам сразу: список блокировок,
      // закладки и уведомления (значок на колокольчике).
      ref.read(blocksProvider);
      ref.read(savedProvider);
      ref.read(notificationsProvider);
    });
    // Push (FCM) — отдельная инфраструктура; пока значок обновляется опросом.
    _poll = Timer.periodic(
      const Duration(seconds: 90),
      (_) => ref.read(notificationsProvider.notifier).refreshQuietly(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(notificationsProvider.notifier).refreshQuietly();
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: widget.navigationShell,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.hair)),
        ),
        child: NavigationBar(
          selectedIndex: widget.navigationShell.currentIndex,
          // goBranch с initialLocation возвращает ветку в корень при повторном
          // тапе по активной вкладке — привычное поведение.
          onDestinationSelected: (index) => widget.navigationShell.goBranch(
            index,
            initialLocation: index == widget.navigationShell.currentIndex,
          ),
          // Порядок вкладок должен совпадать с порядком веток роутера.
          destinations: [
            NavigationDestination(
              icon: Icon(Icons.photo_library_outlined),
              selectedIcon: Icon(Icons.photo_library),
              // Тестовое имя вкладки; позже уйдёт в перевод по выбору языка.
              label: 'Flow',
            ),
            NavigationDestination(
              icon: Icon(Icons.map_outlined),
              selectedIcon: Icon(Icons.map),
              label: 'Pulse',
            ),
            NavigationDestination(
              icon: Icon(Icons.add_circle_outline, size: 30),
              selectedIcon: Icon(Icons.add_circle, size: 30),
              label: 'Создать',
            ),
            NavigationDestination(
              icon: Icon(Icons.forum_outlined),
              selectedIcon: Icon(Icons.forum),
              label: 'Чаты',
            ),
            NavigationDestination(
              icon: UpdateDot(child: Icon(Icons.person_outline)),
              selectedIcon: UpdateDot(child: Icon(Icons.person)),
              label: 'Профиль',
            ),
          ],
        ),
      ),
    );
  }
}
