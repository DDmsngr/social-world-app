import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/debug/app_log.dart';
import '../../../core/debug/log_viewer_screen.dart';
import '../../../core/network/vpn_check.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/state_message.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../events/domain/entities/event.dart';
import '../domain/entities/discover_snapshot.dart';
import '../domain/entities/nearby_person.dart';
import '../domain/entities/place.dart';
import 'providers/discover_providers.dart';
import 'providers/city_provider.dart';
import 'providers/presence_publisher.dart';
import 'widgets/city_picker.dart';
import 'widgets/discover_map.dart';
import 'widgets/map_controls.dart';
import 'widgets/map_object_sheets.dart';

/// Главный экран. Цикл, вокруг которого строится приложение:
/// карта → активность → объект → действие → возврат на карту. Всё остальное
/// (события, моменты, профили) открывается с карты и возвращает на неё.
class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  // Тап по названию города — выбор города; лог-панель переехала на долгое
  // нажатие, потому что короткий тап теперь занят. adb до телефона
  // тестировщика не дотянуться, а спрятанный жест не мозолит глаза.
  void _openLogs() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const LogViewerScreen()));
  }

  void _focus(double? latitude, double? longitude, {double zoom = 16}) {
    if (latitude == null || longitude == null) return;
    ref
        .read(mapFocusProvider.notifier)
        .request(latitude, longitude, zoom: zoom);
  }

  /// Выбор результата поиска или строки «Рядом»: камера идёт к объекту, карточка
  /// открывается поверх карты; у человека без точки открывается профиль.
  void _onSelect(MapSearchResult result) {
    switch (result.kind) {
      case SearchKind.place:
        _focus(result.latitude, result.longitude);
        showPlaceSheet(context, result.payload! as Place);
      case SearchKind.event:
        final event = result.payload! as Event;
        _focus(result.latitude, result.longitude);
        showEventSheet(context, event);
      case SearchKind.nearbyPerson:
        _focus(result.latitude, result.longitude, zoom: 15);
        showPersonSheet(context, result.payload! as NearbyPerson);
      case SearchKind.profile:
        openProfile(context, result.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Пока открыта карта — обновляем свою размытую точку в `locations`.
    // Без этого «Рядом» на боевом бэкенде всегда пустой: читать чужие точки
    // приложение умело, а писать свою — нет.
    ref.watch(presencePublisherProvider);

    final data = ref.watch(discoverDataProvider);
    ref.listen(discoverDataProvider, (_, next) {
      AppLog.add(
        'Карта: данные — ${next.isLoading
            ? 'загрузка'
            : next.hasError
            ? 'ошибка ${next.error}'
            : 'готово'}',
      );
    });
    final view = ref.watch(mapViewProvider);
    final picking = ref.watch(pickingAnchorProvider);
    final anchor = ref.watch(nearbyAnchorProvider);

    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          onTap: () => showCityPicker(context),
          onLongPress: _openLogs,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(ref.watch(cityProvider).name),
              const SizedBox(width: 6),
              const Icon(Icons.expand_more, size: 22),
            ],
          ),
        ),
      ),
      body: data.when(
        // LayoutBuilder — не оформление, а обязательное условие: Pulse
        // строится через StatefulShellRoute.indexedStack (app_router.dart),
        // и go_router монтирует все пять веток нижней навигации разом при
        // входе. Без LayoutBuilder Stack с картой строился в тот же кадр,
        // что и остальные ветки, до того как Scaffold успевал отдать телу
        // окончательные ограничения размера — нативный слой карты создавался
        // с недоопределённым размером и не показывал ни себя, ни соседние
        // виджеты поверх. LayoutBuilder строит детей только после того, как
        // constraints уже посчитаны, и снимает эту гонку.
        data: (snapshot) => LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              children: [
                Positioned.fill(
                  child: DiscoverMap(
                    data: snapshot,
                    places: view.places,
                    events: view.events,
                    people: view.people,
                    // Пока зоны пересчитываются, слой пустой — старые не висят
                    // поверх новых.
                    activity: ref.watch(visibleActivityProvider),
                    activityMode: ref.watch(activityModeProvider),
                    anchor: anchor,
                    focus: ref.watch(mapFocusProvider),
                    filterActive: view.isFiltered,
                    onPlaceTap: (place) => showPlaceSheet(context, place),
                    onEventTap: (event) => showEventSheet(context, event),
                    onPersonTap: (person) => showPersonSheet(context, person),
                    onLongTap: picking
                        ? (lat, lng) {
                            ref
                                .read(nearbyAnchorProvider.notifier)
                                .set(
                                  NearbyAnchor(latitude: lat, longitude: lng),
                                );
                            ref.read(pickingAnchorProvider.notifier).set(false);
                          }
                        : null,
                  ),
                ),
                Positioned(
                  left: AppSpacing.gutter,
                  right: AppSpacing.gutter,
                  top: 12,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      MapSearchBar(
                        onSelect: _onSelect,
                        onOpenFilters: () =>
                            showMapFiltersSheet(context, snapshot.places),
                      ),
                      const SizedBox(height: 8),
                      const MapLayerChips(),
                      if (picking) ...[
                        const SizedBox(height: 8),
                        _PickingBanner(
                          onCancel: () => ref
                              .read(pickingAnchorProvider.notifier)
                              .set(false),
                        ),
                      ],
                    ],
                  ),
                ),
                if (view.isEmpty && view.isFiltered)
                  const Positioned(
                    left: AppSpacing.gutter,
                    right: AppSpacing.gutter,
                    bottom: 148,
                    child: MapEmptyBanner(),
                  ),
                // Один Row вместо двух независимых Positioned: раньше оба
                // считали, что для них хватит места, и на узких экранах
                // переключатель режима наезжал текстом на кнопку «Рядом».
                // Flexible + spaceBetween раздвигает их и ужимает текст
                // переключателя, если места всё равно мало, вместо наложения.
                Positioned(
                  left: AppSpacing.gutter,
                  right: AppSpacing.gutter,
                  bottom: 92,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Flexible(child: MapModeSwitch()),
                      const SizedBox(width: 8),
                      ActionChip(
                        avatar: Icon(
                          Icons.radar,
                          size: 18,
                          color: AppColors.primaryTint,
                        ),
                        label: const Text('Рядом'),
                        onPressed: () =>
                            showNearbySheet(context, onSelect: _onSelect),
                        backgroundColor: AppColors.ink2,
                        side: BorderSide(color: AppColors.hairStrong),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: AppSpacing.gutter,
                  right: AppSpacing.gutter,
                  bottom: 16,
                  child: _CityPulseCard(
                    data: snapshot,
                    view: view,
                    onOpen: () => context.push(Routes.events),
                  ),
                ),
                const MapIntro(),
              ],
            );
          },
        ),
        loading: () => const LoadingView(),
        error: (error, _) => _MapError(
          error: error,
          onRetry: () => ref.invalidate(discoverDataProvider),
        ),
      ),
    );
  }
}

/// Сбой загрузки карты. Самая частая причина в поле — VPN: включили, открыли
/// приложение, выключили — и связь зависла. Поэтому проверяем VPN и говорим
/// прямо, что сделать.
class _MapError extends StatelessWidget {
  const _MapError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: isVpnActive(),
      builder: (context, snapshot) {
        final vpn = snapshot.data ?? false;
        return StateMessage.error(
          title: 'Не удалось загрузить район',
          text: vpn
              ? 'Включён VPN — из-за него карта может не грузиться. '
                    'Отключите VPN и нажмите «Повторить». Если не помогло, '
                    'закройте приложение и откройте снова.'
              : 'Проверьте соединение и нажмите «Повторить». Если вы только '
                    'что выключили VPN, закройте приложение и откройте снова.',
          onAction: onRetry,
        );
      },
    );
  }
}

class _PickingBanner extends StatelessWidget {
  const _PickingBanner({required this.onCancel});

  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.geo.withValues(alpha: 0.95),
      borderRadius: BorderRadius.circular(AppRadius.field),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
        child: Row(
          children: [
            const Icon(
              Icons.touch_app_outlined,
              size: 18,
              color: Colors.black87,
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Удерживайте палец на карте, чтобы выбрать точку',
                style: TextStyle(color: Colors.black87, fontSize: 13),
              ),
            ),
            TextButton(
              onPressed: onCancel,
              child: const Text(
                'Отмена',
                style: TextStyle(color: Colors.black87),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// «Пульс города»: что происходит вокруг прямо сейчас, одной строкой.
/// Тап открывает список событий — отдельной вкладки у них больше нет.
class _CityPulseCard extends StatelessWidget {
  const _CityPulseCard({
    required this.data,
    required this.view,
    required this.onOpen,
  });

  final DiscoverSnapshot data;
  final MapView view;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final level = data.pulseLevel;
    final dot = level >= 2 ? AppColors.primaryTint : AppColors.geo;
    final summary = [
      _plural(view.events.length, 'событие', 'события', 'событий'),
      _plural(view.places.length, 'место', 'места', 'мест'),
      '${view.people.length} рядом',
    ].join(' · ');

    return Semantics(
      button: true,
      label: 'Пульс города: $summary. Открыть события',
      child: Material(
        color: AppColors.ink2.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: AppColors.hairStrong),
            ),
            child: Row(
              children: [
                Container(
                  width: 10 + level * 3,
                  height: 10 + level * 3,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: dot,
                    boxShadow: [
                      BoxShadow(
                        color: dot.withValues(alpha: 0.35),
                        blurRadius: 12,
                        spreadRadius: 3,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Пульс города',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        summary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                Text(
                  'Смотреть',
                  style: TextStyle(
                    color: AppColors.primaryTint,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Icon(Icons.chevron_right, color: AppColors.primaryTint),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _plural(int n, String one, String few, String many) {
  final mod10 = n % 10;
  final mod100 = n % 100;
  final word = mod10 == 1 && mod100 != 11
      ? one
      : mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)
      ? few
      : many;
  return '$n $word';
}
