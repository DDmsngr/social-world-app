import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/links/deep_links.dart';
import '../../../core/router/app_router.dart';
import '../../../core/share/share_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/state_message.dart';
import '../../../core/widgets/sw_widgets.dart';
import '../../events/domain/entities/event.dart';
import '../../events/presentation/providers/events_providers.dart';
import '../../feed/domain/entities/post.dart';
import '../../feed/presentation/providers/feed_providers.dart';
import '../../feed/presentation/widgets/post_card.dart';
import '../../saved/saved.dart';
import '../domain/entities/place.dart';
import 'providers/discover_providers.dart';

/// Место по id: сначала из уже загруженной выборки, иначе адресно.
final placeProvider = FutureProvider.autoDispose.family<Place?, String>((
  ref,
  placeId,
) async {
  final loaded = ref.watch(discoverDataProvider).value?.places ?? const <Place>[];
  for (final place in loaded) {
    if (place.id == placeId) return place;
  }
  return ref.watch(discoverRepositoryProvider).loadPlace(placeId);
});

/// Профиль места: описание, ближайшие события и свежие моменты. Открывается
/// с карточки на карте и по ссылке; «Показать на карте» возвращает на карту.
class PlaceScreen extends ConsumerWidget {
  const PlaceScreen({super.key, required this.placeId});

  final String placeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final place = ref.watch(placeProvider(placeId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Место'),
        leading: IconButton(
          onPressed: () =>
              context.canPop() ? context.pop() : context.go(Routes.home),
          tooltip: 'Назад',
          icon: const Icon(Icons.arrow_back),
        ),
        actions: place.value == null
            ? null
            : [
                _SaveButton(place: place.value!),
                Builder(
                  builder: (context) => IconButton(
                    onPressed: () => ShareService.share(
                      context,
                      target: LinkTarget.place,
                      id: place.value!.id,
                      title: place.value!.title,
                      details: place.value!.category,
                    ),
                    tooltip: 'Поделиться',
                    icon: const Icon(Icons.ios_share),
                  ),
                ),
              ],
      ),
      body: place.when(
        loading: () => const LoadingView(),
        error: (_, _) => StateMessage.error(
          title: 'Место не загрузилось',
          onAction: () => ref.invalidate(placeProvider(placeId)),
        ),
        data: (value) => value == null
            ? const StateMessage(
                title: 'Место не найдено',
                text: 'Возможно, ссылка устарела.',
                icon: Icons.location_off_outlined,
              )
            : _Body(place: value),
      ),
    );
  }
}

class _SaveButton extends ConsumerWidget {
  const _SaveButton({required this.place});

  final Place place;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved =
        ref.watch(savedProvider).value?.contains(savedKey(SavedKind.place, place.id)) ??
        false;
    return IconButton(
      onPressed: () async {
        final result = await ref
            .read(savedProvider.notifier)
            .toggle(SavedKind.place, place.id, title: place.title, subtitle: place.category);
        if (result == null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Не удалось сохранить — нет связи')),
          );
        }
      },
      tooltip: saved ? 'Убрать из сохранённого' : 'Сохранить',
      icon: Icon(saved ? Icons.bookmark : Icons.bookmark_border),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.place});

  final Place place;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final events = [
      for (final event in ref.watch(eventsProvider).value ?? const <Event>[])
        if (event.placeId == place.id && !event.isPast) event,
    ];
    final moments = [
      for (final post in ref.watch(feedProvider).value ?? const <Post>[])
        if (post.placeId == place.id && !post.isRoute) post,
    ];

    return ListView(
      padding: AppSpacing.page(context, top: 16),
      children: [
        SectionLabel(place.category ?? 'Место'),
        const SizedBox(height: 12),
        Text(place.title, style: AppTypography.serif(32)),
        if (place.description != null) ...[
          const SizedBox(height: 12),
          Text(place.description!, style: theme.textTheme.bodyLarge),
        ],
        const SizedBox(height: 18),
        OutlinedButton.icon(
          onPressed: () {
            ref.read(mapFocusProvider.notifier).request(
              place.latitude,
              place.longitude,
              zoom: 16,
            );
            context.go(Routes.home);
          },
          icon: const Icon(Icons.map_outlined),
          label: const Text('Показать на карте'),
        ),
        const SizedBox(height: 26),
        const SectionLabel('Ближайшие события'),
        const SizedBox(height: 12),
        if (events.isEmpty)
          Text('Пока ничего не запланировано.', style: theme.textTheme.bodyMedium)
        else
          for (final event in events)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GlassCard(
                onTap: () => context.push(
                  '${Routes.eventDetail}/${event.id}',
                  extra: event,
                ),
                child: Row(
                  children: [
                    Icon(Icons.event_outlined, color: AppColors.primaryTint),
                    const SizedBox(width: 12),
                    Expanded(child: Text(event.title)),
                    Icon(Icons.chevron_right, color: AppColors.textFaint),
                  ],
                ),
              ),
            ),
        const SizedBox(height: 22),
        const SectionLabel('Моменты здесь'),
        const SizedBox(height: 12),
        if (moments.isEmpty)
          Text('Здесь пока ничего не публиковали.', style: theme.textTheme.bodyMedium)
        else
          for (final post in moments) PostCard(post: post),
      ],
    );
  }
}
