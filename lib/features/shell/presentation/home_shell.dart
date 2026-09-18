import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/update/update_badge.dart';
import '../../../core/update/update_controller.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  @override
  void initState() {
    super.initState();
    // Одна проверка за запуск: оболочка создаётся после входа и живёт до
    // закрытия приложения, так что дёргать сеть чаще незачем.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(updateControllerProvider.notifier).check();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          widget.navigationShell,
          const UpdateBadge(),
        ],
      ),
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
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.photo_library_outlined),
              selectedIcon: Icon(Icons.photo_library),
              label: 'Моменты',
            ),
            NavigationDestination(
              icon: Icon(Icons.map_outlined),
              selectedIcon: Icon(Icons.map),
              label: 'Карта',
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
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Профиль',
            ),
          ],
        ),
      ),
    );
  }
}
