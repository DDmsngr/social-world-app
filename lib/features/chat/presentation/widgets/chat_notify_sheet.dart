import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/debug/app_log.dart';
import '../../../../core/theme/app_colors.dart';
import '../providers/chat_notify_providers.dart';

/// Шторка «Уведомления» одного чата: режим и «выключить на…». Изменения
/// применяются сразу, без кнопки «Сохранить».
Future<void> showChatNotifySheet(
  BuildContext context,
  String conversationId,
  String title,
) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: AppColors.ink2,
    builder: (_) => _ChatNotifySheet(conversationId: conversationId, title: title),
  );
}

class _ChatNotifySheet extends ConsumerWidget {
  const _ChatNotifySheet({required this.conversationId, required this.title});

  final String conversationId;
  final String title;

  static const _modes = [
    (NotifyMode.sound, 'Со звуком', Icons.notifications_active_outlined),
    (NotifyMode.vibrate, 'Только вибрация', Icons.vibration),
    (NotifyMode.silent, 'Тихо — только в шторке', Icons.notifications_none),
    (NotifyMode.off, 'Выключить', Icons.notifications_off_outlined),
  ];

  Future<void> _save(BuildContext context, WidgetRef ref, ChatNotify next) async {
    try {
      await saveChatNotify(ref, conversationId, next);
    } catch (error) {
      AppLog.add('Уведомления чата не сохранились: $error');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось сохранить настройку')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = chatNotifyOf(ref, conversationId);
    final now = DateTime.now();

    DateTime tomorrowMorning() {
      final morning = DateTime(now.year, now.month, now.day, 8);
      return morning.isAfter(now) ? morning : morning.add(const Duration(days: 1));
    }

    final timers = <(String, DateTime)>[
      ('1 час', now.add(const Duration(hours: 1))),
      ('8 часов', now.add(const Duration(hours: 8))),
      ('До утра', tomorrowMorning()),
      ('1 день', now.add(const Duration(days: 1))),
    ];

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Уведомления: $title',
              style: Theme.of(context).textTheme.titleLarge,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            RadioGroup<NotifyMode>(
              groupValue: current.mode,
              onChanged: (mode) {
                if (mode != null) {
                  _save(context, ref, ChatNotify(mode: mode, mutedUntil: current.mutedUntil));
                }
              },
              child: Column(
                children: [
                  for (final (mode, label, icon) in _modes)
                    RadioListTile<NotifyMode>(
                      value: mode,
                      contentPadding: EdgeInsets.zero,
                      secondary: Icon(icon, color: AppColors.textDim),
                      title: Text(label),
                    ),
                ],
              ),
            ),
            const Divider(height: 28),
            Text('Выключить на', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (label, until) in timers)
                  ActionChip(
                    label: Text(label),
                    onPressed: () => _save(
                      context,
                      ref,
                      ChatNotify(mode: current.mode, mutedUntil: until),
                    ),
                  ),
              ],
            ),
            if (current.timerActive) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Без уведомлений до ${_clock(current.mutedUntil!)}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        _save(context, ref, ChatNotify(mode: current.mode)),
                    child: const Text('Включить'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _clock(DateTime time) {
  final hh = time.hour.toString().padLeft(2, '0');
  final mm = time.minute.toString().padLeft(2, '0');
  final today = DateTime.now();
  final sameDay = time.year == today.year && time.month == today.month && time.day == today.day;
  return sameDay ? '$hh:$mm' : '${time.day}.${time.month.toString().padLeft(2, '0')} $hh:$mm';
}
