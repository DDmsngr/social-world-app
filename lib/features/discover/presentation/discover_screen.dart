import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/debug/log_viewer_screen.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/sw_widgets.dart';
import '../../events/domain/entities/event.dart';
import '../../events/presentation/providers/events_providers.dart';
import '../domain/entities/discover_snapshot.dart';
import '../domain/entities/place.dart';
import 'providers/discover_providers.dart';
import 'widgets/discover_map.dart';

class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  int _titleTaps = 0;
  DateTime? _firstTapAt;

  // 5 тапов по заголовку за 2 секунды — открывает лог-панель. adb до
  // телефона тестировщика не дотянуться, а спрятанный жест не мозолит
  // глаза обычному пользователю.
  void _onTitleTap() {
    final now = DateTime.now();
    if (_firstTapAt == null ||
        now.difference(_firstTapAt!) > const Duration(seconds: 2)) {
      _firstTapAt = now;
      _titleTaps = 1;
      return;
    }
    _titleTaps++;
    if (_titleTaps >= 5) {
      _titleTaps = 0;
      _firstTapAt = null;
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const LogViewerScreen()),
      );
    }
  }

  void _openEvent(Event event) =>
      context.push('${Routes.eventDetail}/${event.id}', extra: event);

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(discoverDataProvider);
    // Прошедшие события карте не нужны: она про то, что происходит сейчас.
    final upcoming = [
      for (final event in ref.watch(eventsProvider).value ?? const <Event>[])
        if (!event.isPast) event,
    ];

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: _onTitleTap,
          child: const Text('Сочи'),
        ),
      ),
      body: data.when(
        data: (snapshot) => Stack(
          children: [
            Positioned.fill(
              child: DiscoverMap(
                data: snapshot,
                places: ref.watch(filteredPlacesProvider),
                events: [
                  for (final event in upcoming)
                    if (event.hasLocation) event,
                ],
                onEventTap: _openEvent,
                filterActive: ref.watch(discoverSearchProvider).isNotEmpty ||
                    ref.watch(categoryFilterProvider).isNotEmpty,
                onPlaceTap: (place) => _showPlace(context, place),
              ),
            ),
            Positioned(
              left: AppSpacing.gutter,
              right: AppSpacing.gutter,
              top: 12,
              child: TextField(
                onChanged: ref.read(discoverSearchProvider.notifier).update,
                decoration: InputDecoration(
                  hintText: 'Найти место на карте',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    onPressed: () =>
                        _showFilters(context, ref, snapshot.places),
                    tooltip: 'Фильтры',
                    icon: Icon(
                      Icons.tune,
                      color: ref.watch(categoryFilterProvider).isEmpty
                          ? null
                          : AppColors.primaryTint,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: AppSpacing.gutter,
              right: AppSpacing.gutter,
              bottom: 16,
              child: _CityPulseCard(
                data: snapshot,
                eventCount: upcoming.length,
                onOpen: () => context.push(Routes.events),
              ),
            ),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) =>
            _DiscoverError(onRetry: () => ref.invalidate(discoverDataProvider)),
      ),
    );
  }

  Future<void> _showFilters(
    BuildContext context,
    WidgetRef ref,
    List<Place> allPlaces,
  ) {
    final categories = {
      for (final place in allPlaces)
        if (place.category != null && place.category!.isNotEmpty)
          place.category!,
    }.toList()..sort();

    return showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.all(AppSpacing.gutter),
        child: SheetCard(
          child: Consumer(
            builder: (context, ref, _) {
              final selected = ref.watch(categoryFilterProvider);
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const SectionLabel('Фильтры'),
                      if (selected.isNotEmpty)
                        TextButton(
                          onPressed: () => ref
                              .read(categoryFilterProvider.notifier)
                              .clear(),
                          child: const Text('Сбросить'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
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
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _showPlace(BuildContext context, Place place) =>
      showModalBottomSheet<void>(
        context: context,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (context) => Padding(
          padding: const EdgeInsets.all(AppSpacing.gutter),
          child: SheetCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionLabel(place.category ?? 'Место'),
                const SizedBox(height: 12),
                Text(place.title, style: AppTypography.serif(28)),
                if (place.description != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    place.description!,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ],
            ),
          ),
        ),
      );
}

/// «Пульс города»: что происходит вокруг прямо сейчас, одной строкой.
/// Тап открывает список событий — отдельной вкладки у них больше нет.
class _CityPulseCard extends StatelessWidget {
  const _CityPulseCard({
    required this.data,
    required this.eventCount,
    required this.onOpen,
  });

  final DiscoverSnapshot data;
  final int eventCount;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final level = data.pulseLevel;
    final dot = level >= 2 ? AppColors.primaryTint : AppColors.geo;
    final summary = [
      _plural(eventCount, 'событие', 'события', 'событий'),
      _plural(data.places.length, 'место', 'места', 'мест'),
      '${data.people.length} рядом',
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

class _DiscoverError extends StatelessWidget {
  const _DiscoverError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.gutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Не удалось загрузить район', style: AppTypography.serif(26)),
            const SizedBox(height: 8),
            Text(
              'Проверьте соединение и попробуйте ещё раз.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 18),
            FilledButton(onPressed: onRetry, child: const Text('Повторить')),
          ],
        ),
      ),
    );
  }
}
