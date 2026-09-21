import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/location/device_position.dart';
import '../../../../core/location/distance.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/sw_widgets.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../domain/activity.dart';
import '../../domain/entities/place.dart';
import '../providers/discover_providers.dart';

/// Поле поиска над картой с выпадающими результатами. Ищет места, события и
/// людей; выбранный результат наводит на себя камеру (если у него есть точка)
/// или открывает профиль.
class MapSearchBar extends ConsumerStatefulWidget {
  const MapSearchBar({
    super.key,
    required this.onSelect,
    required this.onOpenFilters,
  });

  final ValueChanged<MapSearchResult> onSelect;
  final VoidCallback onOpenFilters;

  @override
  ConsumerState<MapSearchBar> createState() => _MapSearchBarState();
}

class _MapSearchBarState extends ConsumerState<MapSearchBar> {
  final _controller = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    setState(() {});
    // Пауза в наборе, а не каждая буква: поиск людей ходит на сервер.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), () {
      ref.read(discoverSearchProvider.notifier).update(value);
    });
  }

  void _clear() {
    _debounce?.cancel();
    _controller.clear();
    ref.read(discoverSearchProvider.notifier).update('');
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(discoverSearchProvider);
    // Поле сбросили снаружи («Сбросить фильтры») — очищаем и текст.
    if (query.isEmpty && _controller.text.isNotEmpty && _debounce?.isActive != true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ref.read(discoverSearchProvider).isEmpty) {
          _controller.clear();
          setState(() {});
        }
      });
    }

    final categoryCount = ref.watch(categoryFilterProvider).length;
    final results = ref.watch(mapSearchResultsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          onChanged: _onChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Место, событие или человек',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_controller.text.isNotEmpty)
                  IconButton(
                    onPressed: _clear,
                    tooltip: 'Очистить',
                    icon: const Icon(Icons.close),
                  ),
                IconButton(
                  onPressed: widget.onOpenFilters,
                  tooltip: 'Фильтры',
                  icon: Badge(
                    isLabelVisible: categoryCount > 0,
                    label: Text('$categoryCount'),
                    backgroundColor: AppColors.primary,
                    textColor: AppColors.onPrimary,
                    child: Icon(
                      Icons.tune,
                      color: categoryCount == 0 ? null : AppColors.primaryTint,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_controller.text.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Material(
              color: AppColors.ink2,
              elevation: 6,
              borderRadius: BorderRadius.circular(AppRadius.field),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: results.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                  error: (_, _) => const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Поиск не сработал. Попробуйте ещё раз.'),
                  ),
                  data: (list) => list.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('Ничего не найдено'),
                        )
                      : ListView(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          children: [
                            for (final result in list.take(8))
                              ListTile(
                                dense: true,
                                leading: switch (result.kind) {
                                  SearchKind.nearbyPerson || SearchKind.profile =>
                                    UserAvatar(
                                      name: result.title,
                                      url: result.avatarUrl,
                                      radius: 14,
                                    ),
                                  SearchKind.event => Icon(
                                    Icons.event_outlined,
                                    color: AppColors.primaryTint,
                                  ),
                                  SearchKind.place => Icon(
                                    Icons.place_outlined,
                                    color: AppColors.primaryTint,
                                  ),
                                },
                                title: Text(result.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                                subtitle: result.subtitle == null
                                    ? null
                                    : Text(result.subtitle!),
                                onTap: () {
                                  FocusScope.of(context).unfocus();
                                  _clear();
                                  widget.onSelect(result);
                                },
                              ),
                          ],
                        ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Строка слоёв: каждый чип — включатель слоя со счётчиком того, что он сейчас
/// показывает. Сразу видно, что включено, что выключено и сколько объектов на
/// карте; «Сбросить» появляется, только когда есть что сбрасывать.
class MapLayerChips extends ConsumerWidget {
  const MapLayerChips({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layers = ref.watch(mapLayersProvider);
    final view = ref.watch(mapViewProvider);
    final anchor = ref.watch(nearbyAnchorProvider);

    int countFor(MapLayer layer) => switch (layer) {
      MapLayer.events => view.events.length,
      MapLayer.places => view.places.length,
      MapLayer.people => view.people.length,
      MapLayer.moments => view.momentCount,
    };

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          if (anchor != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: InputChip(
                avatar: Icon(Icons.my_location, size: 16, color: AppColors.geo),
                label: Text('Рядом · ${_radius(anchor.radiusMeters)}'),
                onDeleted: () => ref.read(nearbyAnchorProvider.notifier).clear(),
                deleteButtonTooltipMessage: 'Убрать точку «Рядом»',
                backgroundColor: AppColors.ink2,
                side: BorderSide(color: AppColors.geo.withValues(alpha: 0.6)),
              ),
            ),
          for (final layer in MapLayer.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text('${layer.label} ${countFor(layer)}'),
                selected: layers.contains(layer),
                onSelected: (_) => ref.read(mapLayersProvider.notifier).toggle(layer),
                showCheckmark: false,
                tooltip: layers.contains(layer)
                    ? 'Скрыть «${layer.label}»'
                    : 'Показать «${layer.label}»',
                backgroundColor: AppColors.ink2,
                selectedColor: AppColors.primary,
                labelStyle: TextStyle(
                  fontSize: 13,
                  color: layers.contains(layer)
                      ? AppColors.onPrimary
                      : AppColors.textDim,
                ),
                side: BorderSide(color: AppColors.hair),
              ),
            ),
          if (view.isFiltered)
            ActionChip(
              avatar: Icon(Icons.restart_alt, size: 16, color: AppColors.primaryTint),
              label: const Text('Сбросить'),
              onPressed: () => resetMapFilters(ref),
              backgroundColor: AppColors.ink2,
              side: BorderSide(color: AppColors.hair),
            ),
        ],
      ),
    );
  }
}

String _radius(int meters) =>
    meters >= 1000 ? '${meters ~/ 1000} км' : '$meters м';

/// «Сейчас происходит» / «Где спокойнее» — два режима одного слоя активности.
class MapModeSwitch extends ConsumerWidget {
  const MapModeSwitch({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(activityModeProvider);
    return Material(
      color: AppColors.ink2.withValues(alpha: 0.96),
      borderRadius: BorderRadius.circular(999),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final item in ActivityMode.values)
              _ModeButton(
                label: item.label,
                icon: item == ActivityMode.lively ? Icons.bolt : Icons.spa_outlined,
                selected: mode == item,
                onTap: () => ref.read(activityModeProvider.notifier).set(item),
              ),
          ],
        ),
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 15,
                color: selected ? AppColors.onPrimary : AppColors.textDim,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  color: selected ? AppColors.onPrimary : AppColors.textDim,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Полный набор фильтров: слои со счётчиками, категории мест, режим, сброс.
Future<void> showMapFiltersSheet(BuildContext context, List<Place> allPlaces) {
  final categories = {
    for (final place in allPlaces)
      if (place.category != null && place.category!.isNotEmpty) place.category!,
  }.toList()..sort();

  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => Padding(
      padding: const EdgeInsets.all(AppSpacing.gutter),
      child: SheetCard(
        child: Consumer(
          builder: (context, ref, _) {
            final selected = ref.watch(categoryFilterProvider);
            final layers = ref.watch(mapLayersProvider);
            final mode = ref.watch(activityModeProvider);
            final view = ref.watch(mapViewProvider);

            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const SectionLabel('Фильтры'),
                      if (view.isFiltered)
                        TextButton(
                          onPressed: () => resetMapFilters(ref),
                          child: const Text('Сбросить'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text('Что показывать', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(
                    'Слои влияют и на объекты, и на зоны активности.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final layer in MapLayer.values)
                        FilterChip(
                          label: Text(layer.label),
                          selected: layers.contains(layer),
                          onSelected: (_) =>
                              ref.read(mapLayersProvider.notifier).toggle(layer),
                          showCheckmark: false,
                          backgroundColor: AppColors.card,
                          selectedColor: AppColors.primary,
                          labelStyle: TextStyle(
                            fontSize: 13,
                            color: layers.contains(layer)
                                ? AppColors.onPrimary
                                : AppColors.textDim,
                          ),
                          side: BorderSide(color: AppColors.hair),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text('Категории мест', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 10),
                  if (categories.isEmpty)
                    Text(
                      'Категорий пока нет',
                      style: Theme.of(context).textTheme.bodyMedium,
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final category in categories)
                          ChoiceChip(
                            label: Text(category),
                            selected: selected.contains(category),
                            onSelected: (_) => ref
                                .read(categoryFilterProvider.notifier)
                                .toggle(category),
                            showCheckmark: false,
                            backgroundColor: AppColors.card,
                            selectedColor: AppColors.primary,
                            labelStyle: TextStyle(
                              fontSize: 13,
                              color: selected.contains(category)
                                  ? AppColors.onPrimary
                                  : AppColors.textDim,
                            ),
                            side: BorderSide(color: AppColors.hair),
                          ),
                      ],
                    ),
                  const SizedBox(height: 18),
                  Text('Режим зон', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 10),
                  SegmentedButton<ActivityMode>(
                    showSelectedIcon: false,
                    segments: [
                      for (final item in ActivityMode.values)
                        ButtonSegment(
                          value: item,
                          label: Text(item.label, style: const TextStyle(fontSize: 12.5)),
                        ),
                    ],
                    selected: {mode},
                    onSelectionChanged: (s) =>
                        ref.read(activityModeProvider.notifier).set(s.first),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    view.isEmpty
                        ? 'Ничего не подходит под эти фильтры'
                        : 'Показано: ${view.events.length} событий · '
                              '${view.places.length} мест · ${view.people.length} рядом',
                    style: TextStyle(color: AppColors.primaryTint, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    child: const Text('Готово'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ),
  );
}

/// «Что есть рядом?»: своя позиция или точка на карте, радиус, и сразу список
/// найденного по расстоянию. Постоянный доступ к геолокации не нужен —
/// точку можно выбрать вручную.
Future<void> showNearbySheet(
  BuildContext context, {
  required void Function(MapSearchResult result) onSelect,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => Padding(
      padding: const EdgeInsets.all(AppSpacing.gutter),
      child: SheetCard(
        child: Consumer(
          builder: (context, ref, _) {
            final anchor = ref.watch(nearbyAnchorProvider);
            final view = ref.watch(mapViewProvider);
            final radius = anchor?.radiusMeters ?? 1000;

            Future<void> useDevice() async {
              final result = await requestDevicePosition(context);
              final position = result.position;
              if (position == null) {
                if (result.message != null && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(result.message!)),
                  );
                }
                return;
              }
              ref
                  .read(nearbyAnchorProvider.notifier)
                  .set(
                    NearbyAnchor(
                      latitude: position.latitude,
                      longitude: position.longitude,
                      radiusMeters: radius,
                      isDevice: true,
                    ),
                  );
              ref.read(mapFocusProvider.notifier).request(
                position.latitude,
                position.longitude,
                zoom: 14.5,
              );
            }

            // Результаты: всё, что уже прошло фильтры и попало в радиус,
            // по расстоянию от точки.
            final items = <(double, MapSearchResult)>[];
            if (anchor != null) {
              double dist(double lat, double lng) =>
                  distanceMeters(anchor.latitude, anchor.longitude, lat, lng);
              for (final e in view.events) {
                items.add((
                  dist(e.latitude!, e.longitude!),
                  MapSearchResult(
                    kind: SearchKind.event,
                    id: e.id,
                    title: e.title,
                    subtitle: 'Событие',
                    latitude: e.latitude,
                    longitude: e.longitude,
                    payload: e,
                  ),
                ));
              }
              for (final p in view.places) {
                items.add((
                  dist(p.latitude, p.longitude),
                  MapSearchResult(
                    kind: SearchKind.place,
                    id: p.id,
                    title: p.title,
                    subtitle: p.category ?? 'Место',
                    latitude: p.latitude,
                    longitude: p.longitude,
                    payload: p,
                  ),
                ));
              }
              for (final p in view.people) {
                items.add((
                  dist(p.blurredLatitude, p.blurredLongitude),
                  MapSearchResult(
                    kind: SearchKind.nearbyPerson,
                    id: p.id,
                    title: p.displayName,
                    subtitle: 'Рядом',
                    latitude: p.blurredLatitude,
                    longitude: p.blurredLongitude,
                    avatarUrl: p.avatarUrl,
                    payload: p,
                  ),
                ));
              }
              items.sort((a, b) => a.$1.compareTo(b.$1));
            }

            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionLabel('Рядом'),
                  const SizedBox(height: 12),
                  Text('Что есть рядом?', style: AppTypography.serif(26)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final meters in const [500, 1000, 3000])
                        ChoiceChip(
                          label: Text(_radius(meters)),
                          selected: radius == meters,
                          onSelected: (_) {
                            if (anchor != null) {
                              ref
                                  .read(nearbyAnchorProvider.notifier)
                                  .set(anchor.withRadius(meters));
                            }
                          },
                          showCheckmark: false,
                          backgroundColor: AppColors.card,
                          selectedColor: AppColors.primary,
                          labelStyle: TextStyle(
                            color: radius == meters
                                ? AppColors.onPrimary
                                : AppColors.textDim,
                          ),
                          side: BorderSide(color: AppColors.hair),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: useDevice,
                          icon: const Icon(Icons.my_location, size: 18),
                          label: const Text('Моя позиция'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            ref.read(pickingAnchorProvider.notifier).set(true);
                            Navigator.of(sheetContext).pop();
                          },
                          icon: const Icon(Icons.touch_app_outlined, size: 18),
                          label: const Text('На карте'),
                        ),
                      ),
                    ],
                  ),
                  if (anchor == null) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Выберите свою позицию или удерживайте палец на карте — '
                      'покажем места, события и людей вокруг.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ] else ...[
                    const SizedBox(height: 14),
                    Text(
                      items.isEmpty
                          ? 'В радиусе ${_radius(radius)} ничего нет'
                          : 'В радиусе ${_radius(radius)}: ${items.length}',
                      style: TextStyle(color: AppColors.primaryTint, fontSize: 13),
                    ),
                    for (final (meters, item) in items.take(8))
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(switch (item.kind) {
                          SearchKind.event => Icons.event_outlined,
                          SearchKind.place => Icons.place_outlined,
                          _ => Icons.person_outline,
                        }, color: AppColors.primaryTint),
                        title: Text(item.title),
                        subtitle: Text('${item.subtitle} · ${formatDistance(meters)}'),
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          onSelect(item);
                        },
                      ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () {
                        ref.read(nearbyAnchorProvider.notifier).clear();
                        Navigator.of(sheetContext).pop();
                      },
                      child: const Text('Убрать точку'),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    ),
  );
}

/// Плашка «ничего не найдено» вместо случайных зон и пустой карты без
/// объяснения.
class MapEmptyBanner extends ConsumerWidget {
  const MapEmptyBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: AppColors.ink2.withValues(alpha: 0.96),
      borderRadius: BorderRadius.circular(AppRadius.card),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            Icon(Icons.search_off, color: AppColors.textFaint),
            const SizedBox(width: 12),
            const Expanded(child: Text('По этим фильтрам ничего нет')),
            TextButton(
              onPressed: () => resetMapFilters(ref),
              child: const Text('Сбросить'),
            ),
          ],
        ),
      ),
    );
  }
}

const _introKey = 'map_intro_seen_v1';

/// Короткое знакомство с картой при первом запуске: два шага, без анкет.
/// Разрешения (геолокация) запрашиваются не здесь, а в момент, когда они нужны.
class MapIntro extends StatefulWidget {
  const MapIntro({super.key});

  @override
  State<MapIntro> createState() => _MapIntroState();
}

class _MapIntroState extends State<MapIntro> {
  var _visible = false;
  var _step = 0;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      if (!(prefs.getBool(_introKey) ?? false)) setState(() => _visible = true);
    } catch (_) {
      // Нет хранилища (тесты, веб без прав) — не мешаем, просто не показываем.
    }
  }

  Future<void> _finish() async {
    setState(() => _visible = false);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_introKey, true);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();

    const steps = [
      (
        Icons.map_outlined,
        'Здесь видно, что происходит вокруг тебя',
        'Карта показывает события, места, свежие моменты и зоны, где сейчас '
            'оживлённо.',
      ),
      (
        Icons.tune,
        'Выбирай, что хочешь видеть',
        'Включай и выключай слои сверху, ищи по названию. Хочешь тишины — '
            'переключи «Где спокойнее».',
      ),
    ];
    final (icon, title, text) = steps[_step];
    final last = _step == steps.length - 1;

    return Positioned.fill(
      child: Material(
        color: Colors.black.withValues(alpha: 0.55),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.gutter),
              child: SheetCard(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, size: 30, color: AppColors.primaryTint),
                    const SizedBox(height: 14),
                    Text(title, style: AppTypography.serif(26)),
                    const SizedBox(height: 10),
                    Text(text, style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        TextButton(onPressed: _finish, child: const Text('Пропустить')),
                        const Spacer(),
                        FilledButton(
                          onPressed: last ? _finish : () => setState(() => _step++),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 44),
                            padding: const EdgeInsets.symmetric(horizontal: 22),
                          ),
                          child: Text(last ? 'Понятно' : 'Дальше'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
