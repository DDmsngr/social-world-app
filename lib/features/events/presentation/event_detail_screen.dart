import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/sw_widgets.dart';
import '../../moderation/domain/entities/report_reason.dart';
import '../../moderation/presentation/widgets/report_sheet.dart';
import '../domain/entities/event.dart';
import 'providers/events_providers.dart';

/// Карточка события открывается по тапу из ленты событий. По прямой ссылке
/// (или после перезапуска) события ещё нет под рукой — тогда ищем его в уже
/// загруженном списке, как и в PostDetailScreen для постов.
class EventDetailScreen extends ConsumerWidget {
  const EventDetailScreen({super.key, required this.eventId, this.event});

  final String eventId;
  final Event? event;

  Event? _resolve(WidgetRef ref) {
    if (event != null) return event;
    final list = ref.read(eventsProvider).value ?? const <Event>[];
    for (final item in list) {
      if (item.id == eventId) return item;
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resolved = _resolve(ref);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Событие'),
        leading: IconButton(
          onPressed: () =>
              context.canPop() ? context.pop() : context.go(Routes.home),
          tooltip: 'Назад',
          icon: const Icon(Icons.arrow_back),
        ),
        actions: resolved == null
            ? null
            : [
                IconButton(
                  onPressed: () async {
                    final sent = await showReportSheet(
                      context,
                      target: ReportTarget.event,
                      targetId: resolved.id,
                      subject: resolved.title,
                    );
                    if (!sent || !context.mounted) return;
                    ref.read(eventsProvider.notifier).hide(resolved.id);
                    context.pop();
                  },
                  tooltip: 'Пожаловаться',
                  icon: const Icon(Icons.flag_outlined),
                ),
              ],
      ),
      body: resolved == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.gutter),
                child: Text(
                  'Событие не найдено. Возможно, ссылка устарела.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            )
          : _EventDetailBody(event: resolved),
    );
  }
}

class _EventDetailBody extends ConsumerWidget {
  const _EventDetailBody({required this.event});

  final Event event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        12,
        AppSpacing.gutter,
        24,
      ),
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
          Text(event.description!, style: Theme.of(context).textTheme.bodyLarge),
        ],
        const SizedBox(height: 20),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _InfoRow(
                icon: Icons.person_outline,
                text: 'Организатор: ${event.authorName}',
              ),
              if (event.placeTitle != null) ...[
                const SizedBox(height: 10),
                _InfoRow(icon: Icons.place_outlined, text: event.placeTitle!),
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
        FilledButton(
          onPressed: () async {
            final saved = await ref
                .read(eventsProvider.notifier)
                .toggleJoin(event);
            if (saved || !context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Не удалось записаться — нет связи'),
              ),
            );
          },
          style: event.joinedByMe
              ? FilledButton.styleFrom(
                  backgroundColor: AppColors.card,
                  foregroundColor: AppColors.primaryTint,
                )
              : null,
          child: Text(event.joinedByMe ? 'Вы участвуете' : 'Участвовать'),
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
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '${t.day} ${months[t.month - 1]}, $hh:$mm';
  }

  final end = event.endsAt;
  if (end == null) return fmt(event.startsAt);
  return '${fmt(event.startsAt)} — ${fmt(end)}';
}
