import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/links/deep_links.dart';
import '../../../../core/location/distance.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/share/share_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/sw_widgets.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../events/domain/entities/event.dart';
import '../../../events/presentation/providers/events_providers.dart';
import '../../../feed/domain/entities/post.dart';
import '../../../feed/presentation/providers/feed_providers.dart';
import '../../domain/entities/nearby_person.dart';
import '../../domain/entities/place.dart';
import '../providers/discover_providers.dart';

/// Универсальная карточка объекта на карте. Тап по метке открывает лист с
/// главным и с действиями; «Подробнее» ведёт на полный экран объекта, а
/// возврат с него приходит обратно на карту — цикл
/// карта → объект → действие → карта не рвётся.
Future<void> _show(BuildContext context, Widget child) =>
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(AppSpacing.gutter),
        child: SheetCard(child: child),
      ),
    );

Future<void> showEventSheet(BuildContext context, Event event) =>
    _show(context, _EventSheet(eventId: event.id, fallback: event));

Future<void> showPlaceSheet(BuildContext context, Place place) =>
    _show(context, _PlaceSheet(place: place));

Future<void> showPersonSheet(BuildContext context, NearbyPerson person) =>
    _show(context, _PersonSheet(person: person));

class _EventSheet extends ConsumerWidget {
  const _EventSheet({required this.eventId, required this.fallback});

  final String eventId;
  final Event fallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Живая версия из списка: кнопка «Участвовать» меняется на месте.
    final event =
        (ref.watch(eventsProvider).value ?? const <Event>[])
            .where((e) => e.id == eventId)
            .firstOrNull ??
        fallback;
    final me = ref.watch(currentUserProvider)?.id;
    final isOwner = me == event.authorId;
    final center = ref.watch(discoverCenterProvider).value;
    final theme = Theme.of(context);

    final distance = center != null && event.hasLocation
        ? formatDistance(
            distanceMeters(
              center.latitude,
              center.longitude,
              event.latitude!,
              event.longitude!,
            ),
          )
        : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (event.coverUrl != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.field),
            child: AspectRatio(
              aspectRatio: 16 / 7,
              child: CachedNetworkImage(
                imageUrl: event.coverUrl!,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => ColoredBox(color: AppColors.ink2),
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],
        SectionLabel(_when(event.startsAt)),
        const SizedBox(height: 10),
        Text(event.title, style: AppTypography.serif(26)),
        const SizedBox(height: 8),
        Text(
          [
            if (event.placeTitle != null) event.placeTitle!,
            ?distance,
            '${event.participantCount} идёт',
          ].join(' · '),
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 4),
        InkWell(
          onTap: () {
            Navigator.of(context).pop();
            openProfile(context, event.authorId);
          },
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                UserAvatar(name: event.authorName, url: event.authorAvatarUrl, radius: 11),
                const SizedBox(width: 8),
                Text(
                  event.authorName,
                  style: TextStyle(color: AppColors.primaryTint, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
        if (event.description != null && event.description!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            event.description!,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium,
          ),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: isOwner
                  ? OutlinedButton(
                      onPressed: null,
                      child: const Text('Вы организатор'),
                    )
                  : FilledButton(
                      onPressed: () async {
                        final ok = await ref
                            .read(eventsProvider.notifier)
                            .toggleJoin(event);
                        ref.invalidate(eventParticipantsProvider(event.id));
                        if (!ok && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Не удалось записаться — нет связи'),
                            ),
                          );
                        }
                      },
                      style: event.joinedByMe
                          ? FilledButton.styleFrom(
                              backgroundColor: AppColors.card,
                              foregroundColor: AppColors.primaryTint,
                            )
                          : null,
                      child: Text(event.joinedByMe ? 'Вы участвуете' : 'Участвовать'),
                    ),
            ),
            const SizedBox(width: 8),
            Builder(
              builder: (context) => IconButton.outlined(
                onPressed: () => ShareService.share(
                  context,
                  target: LinkTarget.event,
                  id: event.id,
                  title: event.title,
                  details: '${_when(event.startsAt)}'
                      '${event.placeTitle == null ? '' : ' · ${event.placeTitle}'}',
                ),
                tooltip: 'Поделиться',
                icon: const Icon(Icons.ios_share),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              context.push('${Routes.eventDetail}/${event.id}', extra: event);
            },
            child: const Text('Подробнее'),
          ),
        ),
      ],
    );
  }
}

class _PlaceSheet extends ConsumerWidget {
  const _PlaceSheet({required this.place});

  final Place place;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = [
      for (final event in ref.watch(eventsProvider).value ?? const <Event>[])
        if (event.placeId == place.id && !event.isPast) event,
    ];
    final moments = [
      for (final post in ref.watch(feedProvider).value ?? const <Post>[])
        if (post.placeId == place.id && !post.isRoute) post,
    ];
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(place.category ?? 'Место'),
        const SizedBox(height: 12),
        Text(place.title, style: AppTypography.serif(28)),
        if (place.description != null) ...[
          const SizedBox(height: 10),
          Text(place.description!, style: theme.textTheme.bodyMedium),
        ],
        const SizedBox(height: 12),
        Text(
          [
            if (events.isNotEmpty) '${events.length} ближайших событий',
            if (moments.isNotEmpty) '${moments.length} моментов',
            if (events.isEmpty && moments.isEmpty) 'Пока здесь тихо',
          ].join(' · '),
          style: TextStyle(color: AppColors.primaryTint, fontSize: 13),
        ),
        for (final event in events.take(3))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: InkWell(
              onTap: () {
                Navigator.of(context).pop();
                context.push('${Routes.eventDetail}/${event.id}', extra: event);
              },
              child: Row(
                children: [
                  Icon(Icons.event_outlined, size: 16, color: AppColors.textFaint),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_when(event.startsAt)} · ${event.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  context.push('${Routes.places}/${place.id}');
                },
                child: const Text('Открыть'),
              ),
            ),
            const SizedBox(width: 8),
            Builder(
              builder: (context) => IconButton.outlined(
                onPressed: () => ShareService.share(
                  context,
                  target: LinkTarget.place,
                  id: place.id,
                  title: place.title,
                  details: place.category,
                ),
                tooltip: 'Поделиться',
                icon: const Icon(Icons.ios_share),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PersonSheet extends StatelessWidget {
  const _PersonSheet({required this.person});

  final NearbyPerson person;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('Рядом'),
        const SizedBox(height: 14),
        Row(
          children: [
            UserAvatar(name: person.displayName, url: person.avatarUrl, radius: 28),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(person.displayName, style: AppTypography.serif(26)),
                  Text(
                    'Где-то в этом районе — точное место не показывается',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop();
            openProfile(context, person.id);
          },
          child: const Text('Открыть профиль'),
        ),
      ],
    );
  }
}

String _when(DateTime time) {
  const months = [
    'янв', 'фев', 'мар', 'апр', 'мая', 'июн',
    'июл', 'авг', 'сен', 'окт', 'ноя', 'дек',
  ];
  final local = time.toLocal();
  final now = DateTime.now();
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  final sameDay =
      local.year == now.year && local.month == now.month && local.day == now.day;
  return sameDay
      ? 'сегодня, $hh:$mm'
      : '${local.day} ${months[local.month - 1]}, $hh:$mm';
}
