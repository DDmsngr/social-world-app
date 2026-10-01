import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  /// Нижняя навигация в переписке: только иконки, а пока открыта клавиатура
  /// или панель эмодзи — совсем без неё, место нужнее сообщениям.
  static bool showBottomNav({
    required bool inChat,
    required bool keyboard,
    required bool emojiPanel,
  }) => !(inChat && (keyboard || emojiPanel));

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell>
    with WidgetsBindingObserver {
  Timer? _poll;
  Timer? _presence;
  var _foreground = true;

  /// Раз в минуту, пока приложение открыто: «я в сети». По этой отметке
  /// сервер отправляет сообщения, отложенные «до появления в сети». Не чаще
  /// двух минут — иначе окно «в сети» на сервере закроется между отметками.
  void _touchPresence() {
    if (!Features.chat || !_foreground) return;
    try {
      unawaited(ref.read(chatRepositoryProvider).touchPresence());
    } catch (error) {
      AppLog.add('Присутствие: $error');
    }
  }

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
      _touchPresence();
    });
    _presence = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _touchPresence(),
    );
    // Опрос остаётся страховкой на случай, если пуши выключены в системе.
    _poll = Timer.periodic(
      const Duration(seconds: 90),
      (_) => ref.read(notificationsProvider.notifier).refreshQuietly(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed) {
      ref.read(notificationsProvider.notifier).refreshQuietly();
      _touchPresence();
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _presence?.cancel();
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
    return false;
  }

  /// Индекс вкладки Pulse в `StatefulShellRoute` (порядок веток в роутере).
  static const _pulseTab = 1;

  /// Со дна вкладки — на Pulse, с Pulse — выход. Без PopScope Android 14+
  /// (targetSdk 36, предиктивный «назад») закрывал приложение сам, не
  /// спрашивая Flutter: на корне нечего «отдавать назад», и система считала
  /// событие своим. canPop: false сообщает системе, что «назад» обрабатываем мы.
  void _onBackAtRoot(bool didPop, Object? result) {
    if (didPop) return;
    if (widget.navigationShell.currentIndex != _pulseTab) {
      widget.navigationShell.goBranch(_pulseTab);
    } else {
      SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _onBackAtRoot,
      child: BackButtonListener(
        onBackButtonPressed: _onSystemBack,
        child: _buildShell(context),
      ),
    );
  }

  Widget _buildShell(BuildContext context) {
    final inChat = HomeShell.isConversation(widget.location);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;

    return ValueListenableBuilder<bool>(
      valueListenable: chatEmojiPanelOpen,
      builder: (context, emojiPanel, _) => Scaffold(
        body: widget.navigationShell,
        // Именно null, а не пустой виджет: Scaffold с любой нижней панелью,
        // даже нулевой высоты, считает, что системную полосу внизу занимает
        // она, и убирает отступ из тела — поле ввода уезжало под системные
        // кнопки Android.
        bottomNavigationBar:
            HomeShell.showBottomNav(
              inChat: inChat,
              keyboard: keyboard,
              emojiPanel: emojiPanel,
            )
            ? _navigationBar(compact: inChat)
            : null,
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
