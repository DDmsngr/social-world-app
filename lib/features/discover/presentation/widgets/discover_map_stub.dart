import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/sw_widgets.dart';
import '../../domain/entities/discover_snapshot.dart';
import '../../domain/entities/place.dart';

class DiscoverMap extends StatelessWidget {
  const DiscoverMap({
    super.key,
    required this.data,
    required this.places,
    required this.onPlaceTap,
  });

  final DiscoverSnapshot data;
  final List<Place> places;
  final ValueChanged<Place> onPlaceTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0.4, -0.45),
          radius: 1.15,
          colors: [Color(0xFF26322D), AppColors.ink],
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          104,
          AppSpacing.gutter,
          24,
        ),
        children: [
          const SizedBox(height: 14),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionLabel('Веб-версия'),
                const SizedBox(height: 12),
                Text(
                  'Карта доступна\nв мобильном приложении',
                  style: AppTypography.serif(28),
                ),
                const SizedBox(height: 10),
                Text(
                  'Здесь можно искать места и смотреть пульс района. '
                  'На Android и iOS они появятся прямо на карте.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _PulseCard(data: data),
          const SizedBox(height: 22),
          const SectionLabel('Места рядом'),
          const SizedBox(height: 12),
          if (places.isEmpty)
            Text(
              'По этому запросу ничего не найдено',
              style: Theme.of(context).textTheme.bodyMedium,
            )
          else
            for (final place in places) ...[
              GlassCard(
                padding: const EdgeInsets.all(16),
                onTap: () => onPlaceTap(place),
                child: Row(
                  children: [
                    const Icon(Icons.place_outlined, color: AppColors.primaryTint),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            place.title,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          if (place.category != null)
                            Text(
                              place.category!,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: AppColors.textFaint),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }
}

class _PulseCard extends StatelessWidget {
  const _PulseCard({required this.data});

  final DiscoverSnapshot data;

  @override
  Widget build(BuildContext context) {
    final active = data.pulseLevel >= 2;
    final color = active ? AppColors.primaryTint : AppColors.geo;
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 12 + data.pulseLevel * 4,
            height: 12 + data.pulseLevel * 4,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.35),
                  blurRadius: 16,
                  spreadRadius: 5,
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  active ? 'Район оживает' : 'Спокойный ритм',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(
                  '${data.people.length} человек рядом',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
