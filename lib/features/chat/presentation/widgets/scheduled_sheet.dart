import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/debug/app_log.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/chat_meta.dart';
import '../../domain/schedule_format.dart';
import '../providers/chat_providers.dart';

/// Строка над полем ввода: «Запланировано: 2». Без неё отложенные сообщения
/// после отправки просто исчезали бы из виду.
class ScheduledChip extends ConsumerWidget {
  const ScheduledChip({
    super.key,
    required this.conversationId,
    required this.peerName,
  });

  final String conversationId;
  final String? peerName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count =
        ref.watch(scheduledMessagesProvider(conversationId)).value?.length ?? 0;
    if (count == 0) return const SizedBox.shrink();
    return InkWell(
      onTap: () => showScheduledSheet(
        context,
        conversationId: conversationId,
        peerName: peerName,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.schedule, size: 16, color: AppColors.champagne),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Запланировано: $count',
                style: TextStyle(fontSize: 13, color: AppColors.textDim),
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: AppColors.textFaint),
          ],
        ),
      ),
    );
  }
}

Future<void> showScheduledSheet(
  BuildContext context, {
  required String conversationId,
  required String? peerName,
}) => showModalBottomSheet<void>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  backgroundColor: AppColors.ink2,
  showDragHandle: true,
  builder: (_) =>
      _ScheduledSheet(conversationId: conversationId, peerName: peerName),
);

class _ScheduledSheet extends ConsumerWidget {
  const _ScheduledSheet({required this.conversationId, required this.peerName});

  final String conversationId;
  final String? peerName;

  String _when(ScheduledMessage m) => m.whenOnline
      ? 'Когда ${peerName ?? 'собеседник'} появится в сети'
      : 'Отправится ${formatScheduledAt(m.sendAt!.toLocal(), DateTime.now())}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheduled = ref.watch(scheduledMessagesProvider(conversationId));
    final items = [...?scheduled.value]
      ..sort((a, b) {
        final left = a.sendAt ?? a.createdAt;
        final right = b.sendAt ?? b.createdAt;
        return left.compareTo(right);
      });

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.gutter,
                0,
                AppSpacing.gutter,
                8,
              ),
              child: Text(
                'Запланировано',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.gutter),
                child: Text(
                  'Отложенных сообщений нет',
                  style: TextStyle(color: AppColors.textDim),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final m = items[index];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.gutter,
                      ),
                      leading: Icon(
                        m.whenOnline
                            ? Icons.person_pin_circle_outlined
                            : Icons.schedule,
                        color: AppColors.champagne,
                      ),
                      title: Text(
                        m.text,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${_when(m)}${m.silent ? ' · без звука' : ''}',
                        style: TextStyle(color: AppColors.textDim),
                      ),
                      trailing: IconButton(
                        tooltip: 'Отменить отправку',
                        icon: Icon(
                          Icons.delete_outline_rounded,
                          color: AppColors.danger,
                        ),
                        onPressed: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          try {
                            await ref
                                .read(chatRepositoryProvider)
                                .cancelScheduled(m.id);
                          } catch (error) {
                            AppLog.add('Отмена отложенного: $error');
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('Не удалось отменить'),
                              ),
                            );
                          }
                          ref.invalidate(scheduledMessagesProvider(conversationId));
                        },
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
