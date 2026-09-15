import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/sw_widgets.dart';
import '../domain/entities/place.dart';
import 'providers/discover_providers.dart';
import 'widgets/discover_map.dart';

class DiscoverScreen extends ConsumerWidget {
  const DiscoverScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(discoverDataProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Рядом')),
      body: data.when(
        data: (snapshot) => Stack(
          children: [
            Positioned.fill(
              child: DiscoverMap(
                data: snapshot,
                places: ref.watch(filteredPlacesProvider),
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
                  suffixIcon: ref.watch(discoverSearchProvider).isEmpty
                      ? null
                      : const Icon(Icons.tune, color: AppColors.clay),
                ),
              ),
            ),
            Positioned(
              right: AppSpacing.gutter,
              bottom: 18,
              child: _PulseBadge(
                count: snapshot.people.length,
                level: snapshot.pulseLevel,
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

class _PulseBadge extends StatelessWidget {
  const _PulseBadge({required this.count, required this.level});

  final int count;
  final int level;

  @override
  Widget build(BuildContext context) {
    final color = level >= 2 ? AppColors.clay : AppColors.sage;
    return Material(
      color: AppColors.ink2.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(AppRadius.chip),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.chip),
          border: Border.all(color: AppColors.hairStrong),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8 + level * 2,
              height: 8 + level * 2,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            ),
            const SizedBox(width: 9),
            Text('$count рядом'),
          ],
        ),
      ),
    );
  }
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
