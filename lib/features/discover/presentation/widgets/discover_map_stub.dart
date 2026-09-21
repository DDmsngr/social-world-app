import 'package:flutter/material.dart';

import '../../../../core/location/distance.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/sw_widgets.dart';
import '../../../events/domain/entities/event.dart';
import '../../domain/activity.dart';
import '../../domain/entities/discover_snapshot.dart';
import '../../domain/entities/nearby_person.dart';
import '../../domain/entities/place.dart';
import '../providers/discover_providers.dart';
import 'map_types.dart';

/// Веб не компилирует MapKit, поэтому вместо карты — список того же самого:
/// зоны активности, события, места и люди с теми же фильтрами и поиском.
class DiscoverMap extends StatelessWidget {
  const DiscoverMap({
    super.key,
    required this.data,
    required this.places,
    required this.onPlaceTap,
    this.events = const [],
    this.people = const [],
    this.activity = const [],
    this.activityMode = ActivityMode.lively,
    this.anchor,
    this.focus,
    this.onEventTap,
    this.onPersonTap,
    this.onLongTap,
    this.filterActive = false,
  });

  final DiscoverSnapshot data;
  final List<Place> places;
  final ValueChanged<Place> onPlaceTap;
  final List<Event> events;
  final List<NearbyPerson> people;
  final ValueChanged<Event>? onEventTap;
  final ValueChanged<NearbyPerson>? onPersonTap;
  final List<ActivityCell> activity;
  final ActivityMode activityMode;
  final NearbyAnchor? anchor;
  final MapFocus? focus;
  final void Function(double latitude, double longitude)? onLongTap;
  final bool filterActive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final zones = [
      for (final cell in activity)
        if (cell.intensityFor(activityMode) > 0.04) cell,
    ];

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0.4, -0.45),
          radius: 1.15,
          colors: [AppColors.card, AppColors.ink],
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          170,
          AppSpacing.gutter,
          140,
        ),
        children: [
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
                  'Здесь можно искать и фильтровать всё, что на карте. '
                  'На Android и iOS это рисуется прямо на карте.',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _PulseCard(data: data),
          if (zones.isNotEmpty) ...[
            const SizedBox(height: 22),
            SectionLabel(
              activityMode == ActivityMode.lively
                  ? 'Где сейчас оживлённо'
                  : 'Где спокойнее',
            ),
            const SizedBox(height: 12),
            for (final cell in zones.take(5))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _ZoneRow(cell: cell, mode: activityMode, data: data),
              ),
          ],
          if (events.isNotEmpty) ...[
            const SizedBox(height: 22),
            const SectionLabel('События'),
            const SizedBox(height: 12),
            for (final event in events)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _Row(
                  icon: Icons.event_outlined,
                  title: event.title,
                  subtitle: event.placeTitle,
                  onTap: () => onEventTap?.call(event),
                ),
              ),
          ],
          const SizedBox(height: 22),
          const SectionLabel('Места'),
          const SizedBox(height: 12),
          if (places.isEmpty)
            Text(
              'По этому запросу мест не найдено',
              style: theme.textTheme.bodyMedium,
            )
          else
            for (final place in places)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _Row(
                  icon: Icons.place_outlined,
                  title: place.title,
                  subtitle: place.category,
                  onTap: () => onPlaceTap(place),
                ),
              ),
          if (people.isNotEmpty) ...[
            const SizedBox(height: 22),
            const SectionLabel('Рядом'),
            const SizedBox(height: 12),
            for (final person in people)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _Row(
                  icon: Icons.person_outline,
                  title: person.displayName,
                  subtitle: 'приблизительно',
                  onTap: () => onPersonTap?.call(person),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, color: AppColors.primaryTint),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                if (subtitle != null)
                  Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: AppColors.textFaint),
        ],
      ),
    );
  }
}

class _ZoneRow extends StatelessWidget {
  const _ZoneRow({required this.cell, required this.mode, required this.data});

  final ActivityCell cell;
  final ActivityMode mode;
  final DiscoverSnapshot data;

  @override
  Widget build(BuildContext context) {
    final intensity = cell.intensityFor(mode);
    final away = formatDistance(
      distanceMeters(
        data.centerLatitude,
        data.centerLongitude,
        cell.latitude,
        cell.longitude,
      ),
    );

    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$away от центра · событий ${cell.eventCount}, мест ${cell.placeCount}, '
                  'моментов ${cell.momentCount}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: intensity.clamp(0.05, 1),
                    minHeight: 6,
                    color: mode == ActivityMode.calm
                        ? AppColors.textDim
                        : AppColors.primaryTint,
                    backgroundColor: AppColors.hair,
                  ),
                ),
              ],
            ),
          ),
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
