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
import '../../../core/widgets/glass_surface.dart';
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
        // Тело НЕ уходит под панель (extendBody выключен): первая версия со
        // стеклом поверх контента спрятала кнопки Pulse за меню, а размытие
        // живого списка под панелью тормозило прокрутку каналов.
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
            ? GlassNavBar(
                compact: inChat,
                selectedIndex: widget.navigationShell.currentIndex,
                // goBranch с initialLocation возвращает ветку в корень при
                // повторном тапе по активной вкладке — привычное поведение.
                onSelected: (index) => widget.navigationShell.goBranch(
                  index,
                  initialLocation: index == widget.navigationShell.currentIndex,
                ),
              )
            : null,
      ),
    );
  }
}

/// Вкладка нижней панели. Порядок должен совпадать с порядком веток роутера.
typedef _Tab = ({IconData icon, IconData selected, String label, bool update});

const _tabs = <_Tab>[
  // Тестовые имена вкладок; позже уйдут в перевод по выбору языка.
  (icon: Icons.photo_library_outlined, selected: Icons.photo_library, label: 'Flow', update: false),
  (icon: Icons.map_outlined, selected: Icons.map, label: 'Pulse', update: false),
  (icon: Icons.add_circle_outline, selected: Icons.add_circle, label: 'Создать', update: false),
  (icon: Icons.forum_outlined, selected: Icons.forum, label: 'Чаты', update: false),
  (icon: Icons.person_outline, selected: Icons.person, label: 'Профиль', update: true),
];

/// Нижняя панель «жидкое стекло» (фрейм «Liquid Glass — Regular» в макете):
/// плавающая плашка с размытием того, что под ней, и подписями.
///
/// В переписке она перетекает в компактную плашку из одних иконок по центру —
/// место нужнее сообщениям, а переключиться на другую вкладку всё ещё можно
/// одним касанием. Переход анимирован: ширина и высота плашки меняются
/// плавно, подписи растворяются.
class GlassNavBar extends StatelessWidget {
  const GlassNavBar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    this.compact = false,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool compact;

  static const _duration = Duration(milliseconds: 260);

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final width = MediaQuery.sizeOf(context).width;
    // Полная — почти во всю ширину (368 из 402 в макете), компактная — по
    // размеру иконок.
    final targetWidth = compact ? 5 * 52.0 + 16 : width - 32;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 10 + bottom),
      child: Center(
        heightFactor: 1,
        child: AnimatedContainer(
          duration: _duration,
          curve: Curves.easeOutCubic,
          width: targetWidth,
          height: compact ? 52 : 64,
          child: GlassSurface(
            // Без BackdropFilter: под панелью пустой фон, размывать нечего, а
            // фильтр на каждом кадре — лишняя нагрузка на слабых телефонах.
            blur: 0,
            radius: compact ? 26 : 30,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                for (var i = 0; i < _tabs.length; i++)
                  Expanded(child: _item(context, i)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _item(BuildContext context, int index) {
    final tab = _tabs[index];
    final selected = index == selectedIndex;
    // Выбранная вкладка — акцентом, как «Рядом» в макете.
    final color = selected ? AppColors.primaryTint : AppColors.textDim;
    Widget icon = Icon(
      selected ? tab.selected : tab.icon,
      size: index == 2 ? 28 : 24,
      color: color,
    );
    if (tab.update) icon = UpdateDot(child: icon);

    return Semantics(
      selected: selected,
      button: true,
      label: '${tab.label}, вкладка ${index + 1} из ${_tabs.length}',
      excludeSemantics: true,
      child: InkResponse(
        onTap: () {
          HapticFeedback.selectionClick();
          onSelected(index);
        },
        radius: 28,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            AnimatedSize(
              duration: _duration,
              curve: Curves.easeOutCubic,
              child: compact
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        tab.label,
                        maxLines: 1,
                        overflow: TextOverflow.fade,
                        softWrap: false,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                          color: color,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
