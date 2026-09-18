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
import 'providers/events_providers.dart';
import 'widgets/event_card.dart';

class EventsScreen extends ConsumerWidget {
  const EventsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(eventsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('События'),
        actions: [
          IconButton(
            onPressed: () => ref.read(eventsProvider.notifier).refresh(),
            tooltip: 'Обновить',
            icon: const Icon(Icons.refresh, color: AppColors.textDim),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: events.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => _EventsMessage(
          title: 'Не удалось загрузить',
          text: 'Проверьте соединение и попробуйте ещё раз.',
          actionLabel: 'Повторить',
          onAction: () => ref.read(eventsProvider.notifier).refresh(),
        ),
        data: (list) {
          if (list.isEmpty) {
            return const _EventsMessage(
              title: 'Пока ничего не запланировано',
              text: 'Создайте первое событие во вкладке «Создать».',
            );
          }

          return RefreshIndicator(
            color: AppColors.primaryTint,
            backgroundColor: AppColors.ink2,
            onRefresh: () => ref.read(eventsProvider.notifier).refresh(),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.gutter,
                12,
                AppSpacing.gutter,
                24,
              ),
              itemCount: list.length,
              itemBuilder: (context, index) {
                final event = list[index];
                return EventCard(
                  event: event,
                  onTap: () => context.push(
                    '${Routes.eventDetail}/${event.id}',
                    extra: event,
                  ),
                  onToggleJoin: () =>
                      ref.read(eventsProvider.notifier).toggleJoin(event),
                  onReport: () async {
                    final sent = await showReportSheet(
                      context,
                      target: ReportTarget.event,
                      targetId: event.id,
                      subject: event.title,
                    );
                    if (!sent || !context.mounted) return;
                    ref.read(eventsProvider.notifier).hide(event.id);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Жалоба отправлена')),
                    );
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _EventsMessage extends StatelessWidget {
  const _EventsMessage({
    required this.title,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.gutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionLabel('События'),
            const SizedBox(height: 14),
            Text(title, style: AppTypography.serif(30)),
            const SizedBox(height: 10),
            Text(text, style: Theme.of(context).textTheme.bodyMedium),
            if (actionLabel != null) ...[
              const SizedBox(height: 18),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
