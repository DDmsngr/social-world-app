import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/debug/app_log.dart';
import '../../../core/errors/friendly_error.dart';
import '../../../core/links/deep_links.dart';
import '../../../core/location/distance.dart';
import '../../../core/router/app_router.dart';
import '../../../core/share/share_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/state_message.dart';
import '../../../core/widgets/sw_widgets.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../discover/presentation/providers/discover_providers.dart';
import '../../feed/presentation/post_actions.dart';
import '../../moderation/domain/entities/report_reason.dart';
import '../../moderation/presentation/widgets/report_sheet.dart';
import '../../profile/domain/profile_models.dart';
import '../../routes/domain/entities/city_route.dart';
import '../../routes/presentation/widgets/route_map.dart';
import '../../routes/presentation/widgets/route_map_marker.dart';
import '../../saved/saved.dart';
import '../domain/entities/event.dart';
import 'providers/events_providers.dart';

/// Карточка события. Данные берутся из общего списка событий, а не из
/// «снимка», с которым экран открыли: иначе после «Участвовать» кнопка и
/// счётчик оставались прежними, пока человек не выйдет и не зайдёт заново.
class EventDetailScreen extends ConsumerStatefulWidget {
  const EventDetailScreen({super.key, required this.eventId, this.event});

  final String eventId;

  /// Снимок из списка — показываем сразу, пока свежие данные не подъехали.
  final Event? event;

  @override
  ConsumerState<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends ConsumerState<EventDetailScreen> {
  var _loading = false;
  var _failed = false;

  @override
  void initState() {
    super.initState();
    _ensureLoaded();
  }

  Future<void> _ensureLoaded() async {
    final controller = ref.read(eventsProvider.notifier);
    // `state.value` может быть ещё null, если экран открыт по ссылке до
    // первой загрузки списка: тогда дожидаемся её или берём событие адресно.
    if (controller.byId(widget.eventId) != null) return;

    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final event = await controller.ensure(widget.eventId);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = event == null && widget.event == null;
      });
    } catch (error) {
      AppLog.add('Событие не загрузилось: $error');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = widget.event == null;
      });
    }
  }

  Event? _current(List<Event> list) {
    for (final item in list) {
      if (item.id == widget.eventId) return item;
    }
    return widget.event;
  }

  void _back() => context.canPop() ? context.pop() : context.go(Routes.home);

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(eventsProvider).value ?? const <Event>[];
    final event = _current(list);

    // Событие исчезло из списка (отменено, скрыто жалобой или блокировкой) —
    // страница закрывается вместе с ним.
    ref.listen(eventsProvider, (previous, next) {
      final was = previous?.value?.any((e) => e.id == widget.eventId) ?? false;
      final still = next.value?.any((e) => e.id == widget.eventId) ?? false;
      if (next.hasValue && was && !still && mounted) _back();
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Событие'),
        leading: IconButton(
          onPressed: _back,
          tooltip: 'Назад',
          icon: const Icon(Icons.arrow_back),
        ),
        actions: event == null ? null : _actions(event),
      ),
      body: event != null
          ? _EventDetailBody(event: event)
          : _loading
          ? const LoadingView()
          : _failed
          ? StateMessage(
              title: 'Событие недоступно',
              text: 'Оно отменено, удалено или ссылка устарела.',
              icon: Icons.event_busy_outlined,
              actionLabel: 'Повторить',
              onAction: _ensureLoaded,
            )
          : const LoadingView(),
    );
  }

  List<Widget> _actions(Event event) {
    final me = ref.watch(currentUserProvider)?.id;
    final isOwner = me != null && me == event.authorId;
    final saved =
        ref.watch(savedProvider).value?.contains(savedKey(SavedKind.event, event.id)) ??
        false;

    return [
      IconButton(
        onPressed: () async {
          final result = await ref
              .read(savedProvider.notifier)
              .toggle(
                SavedKind.event,
                event.id,
                title: event.title,
                subtitle: event.placeTitle,
              );
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                switch (result) {
                  true => 'Событие сохранено',
                  false => 'Убрано из «Сохранённого»',
                  null => 'Не удалось сохранить — нет связи',
                },
              ),
            ),
          );
        },
        tooltip: saved ? 'Убрать из сохранённого' : 'Сохранить',
        icon: Icon(saved ? Icons.bookmark : Icons.bookmark_border),
      ),
      Builder(
        builder: (context) => IconButton(
          onPressed: () => ShareService.share(
            context,
            target: LinkTarget.event,
            id: event.id,
            title: event.title,
            details: _shareDetails(event),
          ),
          tooltip: 'Поделиться',
          icon: const Icon(Icons.ios_share),
        ),
      ),
      PopupMenuButton<String>(
        tooltip: 'Действия',
        color: AppColors.ink2,
        onSelected: (value) => _onMenu(value, event),
        itemBuilder: (_) => [
          // Своё и чужое разведено правами, а не одной кнопкой-флажком:
          // организатору жалоба на собственное событие не предлагается.
          if (isOwner)
            const PopupMenuItem(value: 'cancel', child: Text('Отменить событие'))
          else ...const [
            PopupMenuItem(value: 'report', child: Text('Пожаловаться')),
            PopupMenuItem(value: 'mute', child: Text('Скрыть организатора')),
            PopupMenuItem(value: 'block', child: Text('Заблокировать организатора')),
          ],
        ],
      ),
    ];
  }

  Future<void> _onMenu(String value, Event event) async {
    switch (value) {
      case 'cancel':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Отменить событие?'),
            content: const Text('Участникам придёт уведомление об отмене.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Нет'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Отменить событие'),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
        try {
          await ref.read(eventsRepositoryProvider).deleteEvent(event.id);
          ref.read(eventsProvider.notifier).remove(event.id);
        } catch (error) {
          AppLog.add('Событие не отменилось: $error');
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(friendlyError(error, fallback: 'Не удалось отменить'))),
          );
        }
      case 'report':
        final sent = await showReportSheet(
          context,
          target: ReportTarget.event,
          targetId: event.id,
          authorId: event.authorId,
          subject: event.title,
        );
        if (!sent || !mounted) return;
        ref.read(eventsProvider.notifier).hide(event.id);
      case 'mute' || 'block':
        await blockAuthor(
          context,
          ref,
          userId: event.authorId,
          name: event.authorName,
          avatarUrl: event.authorAvatarUrl,
          kind: value == 'block' ? BlockKind.block : BlockKind.mute,
        );
    }
  }
}

String _shareDetails(Event event) => [
  _formatRange(event),
  if (event.placeTitle != null) event.placeTitle!,
].join(' · ');

class _EventDetailBody extends ConsumerWidget {
  const _EventDetailBody({required this.event});

  final Event event;

  Future<void> _toggleJoin(BuildContext context, WidgetRef ref) async {
    final saved = await ref.read(eventsProvider.notifier).toggleJoin(event);
    // Список участников зависит от того же действия — перечитываем его сразу.
    ref.invalidate(eventParticipantsProvider(event.id));
    if (saved || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Не удалось записаться — нет связи')),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserProvider)?.id;
    final isOwner = me != null && me == event.authorId;
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

    return ListView(
      padding: AppSpacing.page(context),
      children: [
        if (event.coverUrl != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.card),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: CachedNetworkImage(
                imageUrl: event.coverUrl!,
                fit: BoxFit.cover,
                placeholder: (_, _) => ColoredBox(color: AppColors.ink2),
                errorWidget: (_, _, _) => ColoredBox(color: AppColors.ink2),
              ),
            ),
          ),
        if (event.coverUrl != null) const SizedBox(height: 18),
        SectionLabel(_formatRange(event)),
        const SizedBox(height: 12),
        Text(event.title, style: AppTypography.serif(30)),
        if (event.description != null && event.description!.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(event.description!, style: theme.textTheme.bodyLarge),
        ],
        const SizedBox(height: 20),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: () => openProfile(context, event.authorId),
                borderRadius: BorderRadius.circular(8),
                child: Row(
                  children: [
                    UserAvatar(
                      name: event.authorName,
                      url: event.authorAvatarUrl,
                      radius: 14,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Организатор: ${event.authorName}',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    Icon(Icons.chevron_right, color: AppColors.textFaint),
                  ],
                ),
              ),
              if (event.placeTitle != null) ...[
                const SizedBox(height: 10),
                _InfoRow(
                  icon: Icons.place_outlined,
                  text: [
                    event.placeTitle!,
                    ?distance,
                  ].join(' · '),
                ),
              ],
              const SizedBox(height: 10),
              _InfoRow(
                icon: Icons.groups_outlined,
                text: '${event.participantCount} идёт',
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        if (isOwner)
          GlassCard(
            child: Row(
              children: [
                Icon(Icons.verified_outlined, color: AppColors.primaryTint),
                const SizedBox(width: 10),
                const Expanded(child: Text('Вы организатор этого события')),
              ],
            ),
          )
        else
          FilledButton(
            onPressed: () => _toggleJoin(context, ref),
            style: event.joinedByMe
                ? FilledButton.styleFrom(
                    backgroundColor: AppColors.card,
                    foregroundColor: AppColors.primaryTint,
                  )
                : null,
            child: Text(event.joinedByMe ? 'Вы участвуете' : 'Участвовать'),
          ),
        if (event.hasRoute) ...[
          const SizedBox(height: 26),
          _RouteSection(event: event),
        ],
        const SizedBox(height: 26),
        _Participants(eventId: event.id),
      ],
    );
  }
}

/// Маршрут события: линия на карте и список точек по порядку.
class _RouteSection extends StatelessWidget {
  const _RouteSection({required this.event});

  final Event event;

  @override
  Widget build(BuildContext context) {
    final points = event.routePoints;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('Маршрут'),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: SizedBox(
            height: 220,
            child: RouteMap(
              path: [
                for (final point in points)
                  RouteCoordinate(point.latitude, point.longitude),
              ],
              markers: [
                for (var i = 0; i < points.length; i++)
                  RouteMapMarker(
                    latitude: points[i].latitude,
                    longitude: points[i].longitude,
                    label: '${i + 1}',
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < points.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 11,
                  backgroundColor: AppColors.primary,
                  child: Text(
                    '${i + 1}',
                    style: AppTypography.serif(12, color: AppColors.onPrimary),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    points[i].title ??
                        '${points[i].latitude.toStringAsFixed(4)}, '
                            '${points[i].longitude.toStringAsFixed(4)}',
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Participants extends ConsumerWidget {
  const _Participants({required this.eventId});

  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final participants = ref.watch(eventParticipantsProvider(eventId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('Кто идёт'),
        const SizedBox(height: 12),
        participants.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, _) => Row(
            children: [
              const Expanded(child: Text('Список не загрузился')),
              TextButton(
                onPressed: () => ref.invalidate(eventParticipantsProvider(eventId)),
                child: const Text('Повторить'),
              ),
            ],
          ),
          data: (list) => list.isEmpty
              ? Text(
                  'Пока никто не записался. Будьте первым.',
                  style: Theme.of(context).textTheme.bodyMedium,
                )
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final person in list)
                      ActionChip(
                        avatar: UserAvatar(
                          name: person.displayName,
                          url: person.avatarUrl,
                          radius: 11,
                        ),
                        label: Text(person.displayName),
                        onPressed: () => openProfile(context, person.profileId),
                        backgroundColor: AppColors.card,
                        side: BorderSide(color: AppColors.hair),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: AppColors.textFaint),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ],
    );
  }
}

String _formatRange(Event event) {
  const months = [
    'янв', 'фев', 'мар', 'апр', 'мая', 'июн',
    'июл', 'авг', 'сен', 'окт', 'ноя', 'дек',
  ];
  String fmt(DateTime t) {
    final local = t.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '${local.day} ${months[local.month - 1]}, $hh:$mm';
  }

  final end = event.endsAt;
  if (end == null) return fmt(event.startsAt);
  return '${fmt(event.startsAt)} — ${fmt(end)}';
}
