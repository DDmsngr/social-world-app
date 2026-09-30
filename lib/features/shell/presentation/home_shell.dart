import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/feature_flags.dart';
import '../../../core/debug/app_log.dart';
import '../../../core/push/push_service.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/update/update_controller.dart';
import '../../../core/update/update_dot.dart';
import '../../chat/presentation/providers/chat_providers.dart';
import '../../notifications/notifications.dart';
import '../../profile/presentation/providers/profile_providers.dart';
import '../../saved/saved.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({
    super.key,
    required this.navigationShell,
    this.location = '',
  });

  final StatefulNavigationShell navigationShell;

  /// Текущий адрес: в открытой переписке навигация сжимается до иконок.
  final String location;

  /// Открыта конкретная переписка (или экран внутри неё), а не список чатов.
  static bool isConversation(String location) =>
      location.startsWith('${Routes.chats}/') &&
      location != '${Routes.chats}/new-group';

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
      // Ключи шифрования публикуются при создании репозитория чатов. Делаем
      // это сразу после входа, а не при первом заходе во вкладку «Чаты»:
      // иначе человеку нельзя написать, пока он сам туда не заглянет.
      if (Features.chat) {
        try {
          ref.read(chatRepositoryProvider);
        } catch (error) {
          AppLog.add('Чаты не инициализировались: $error');
        }
      }
      ref.read(pushServiceProvider).start();
    });
    // Опрос остаётся страховкой на случай, если пуши выключены в системе.
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

  /// Системный «назад»: сначала на предыдущий экран (с уважением к PopScope —
  /// например, к подтверждению в записи маршрута), со дна любой вкладки — на
  /// Pulse, и только с Pulse приложение закрывается. Оболочка остаётся в дереве
  /// под открытыми поверх неё экранами, поэтому слушатель ловит и их.
  Future<bool> _onSystemBack() async {
    final router = ref.read(routerProvider);
    if (await router.routerDelegate.popRoute()) return true;
    // Страховка: стандартный разбор не всегда видит экран, открытый поверх
    // вкладок, и тогда Android закрывал приложение прямо из настроек.
    if (router.canPop()) {
      router.pop();
      return true;
    }
    if (router.state.matchedLocation != Routes.home) {
      router.go(Routes.home);
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return BackButtonListener(
      onBackButtonPressed: _onSystemBack,
      child: _buildShell(context),
    );
  }

  Widget _buildShell(BuildContext context) {
    final inChat = HomeShell.isConversation(widget.location);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;

    return Scaffold(
      body: widget.navigationShell,
      // В переписке навигация — только иконки, без подписей, а пока занято
      // поле ввода (клавиатура или эмодзи) — не видна совсем: место отдаём
      // сообщениям.
      bottomNavigationBar: ValueListenableBuilder<bool>(
        valueListenable: chatInputActive,
        builder: (context, inputActive, _) {
          if (inChat && (keyboard || inputActive)) {
            return const SizedBox.shrink();
          }
          return _navigationBar(compact: inChat);
        },
      ),
    );
  }

  Widget _navigationBar({required bool compact}) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.hair)),
      ),
      child: NavigationBar(
        height: compact ? 52 : null,
        labelBehavior: compact
            ? NavigationDestinationLabelBehavior.alwaysHide
            : null,
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
    );
  }
}
