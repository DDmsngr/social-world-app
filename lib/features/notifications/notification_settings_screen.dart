import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/audio/bell_sound.dart';
import '../../core/errors/friendly_error.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/state_message.dart';
import '../../core/widgets/sw_widgets.dart';
import 'notification_prefs.dart';

/// Настройки уведомлений: что присылать, звук колокольчика и тихие часы.
/// Выключенная категория не доходит ни пушем, ни в список уведомлений.
class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  Future<void> _run(BuildContext context, Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(error, fallback: 'Не удалось сохранить'))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(notificationPrefsProvider);
    final controller = ref.read(notificationPrefsProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Уведомления'),
        leading: IconButton(
          onPressed: () => context.canPop() ? context.pop() : context.go(Routes.settings),
          tooltip: 'Назад',
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: prefs.when(
        loading: () => const LoadingView(),
        error: (_, _) => StateMessage.error(
          onAction: () => ref.invalidate(notificationPrefsProvider),
        ),
        data: (value) => ListView(
          padding: AppSpacing.page(context, top: AppSpacing.gutter),
          children: [
            const SectionLabel('Что присылать'),
            const SizedBox(height: 12),
            for (final category in NotificationCategory.values) ...[
              GlassCard(
                padding: const EdgeInsets.fromLTRB(18, 2, 8, 2),
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: value.isOn(category),
                  onChanged: (on) => _run(context, () => controller.setCategory(category, on)),
                  title: Text(category.title),
                  subtitle: Text(category.subtitle),
                ),
              ),
              const SizedBox(height: 8),
            ],
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 6),
              child: Text(
                'Звонки приходят всегда. Тихий режим отдельного чата настраивается в самом чате.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: 18),
            const SectionLabel('Колокольчик'),
            const SizedBox(height: 12),
            const _BellSoundSwitch(),
            const SizedBox(height: 26),
            const SectionLabel('Тихие часы'),
            const SizedBox(height: 12),
            _QuietHours(
              prefs: value,
              onChanged: (from, to) => _run(context, () => controller.setQuiet(from, to)),
            ),
          ],
        ),
      ),
    );
  }
}

class _BellSoundSwitch extends StatefulWidget {
  const _BellSoundSwitch();

  @override
  State<_BellSoundSwitch> createState() => _BellSoundSwitchState();
}

class _BellSoundSwitchState extends State<_BellSoundSwitch> {
  bool? _on;

  @override
  void initState() {
    super.initState();
    BellSound.isEnabled().then((value) {
      if (mounted) setState(() => _on = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final on = _on;
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(18, 2, 8, 2),
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: on ?? true,
        onChanged: on == null
            ? null
            : (value) {
                setState(() => _on = value);
                BellSound.setEnabled(value);
                if (value) BellSound.play(force: true);
              },
        title: const Text('Звук колокольчика'),
        subtitle: const Text(
          'Когда приложение открыто, новое уведомление показывается колокольчиком',
        ),
      ),
    );
  }
}

/// Тихие часы: уведомление приходит, но без звука и вибрации.
class _QuietHours extends StatelessWidget {
  const _QuietHours({required this.prefs, required this.onChanged});

  final NotificationPrefs prefs;
  final void Function(int? from, int? to) onChanged;

  static const _defaultFrom = 23 * 60;
  static const _defaultTo = 7 * 60;

  static String _label(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

  Future<int?> _pick(BuildContext context, int initial) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initial ~/ 60, minute: initial % 60),
      helpText: 'Время',
      cancelText: 'Отмена',
      confirmText: 'Готово',
    );
    return picked == null ? null : picked.hour * 60 + picked.minute;
  }

  @override
  Widget build(BuildContext context) {
    final from = prefs.quietFrom ?? _defaultFrom;
    final to = prefs.quietTo ?? _defaultTo;
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(18, 2, 8, 8),
      child: Column(
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: prefs.hasQuietHours,
            onChanged: (on) => on ? onChanged(from, to) : onChanged(null, null),
            title: const Text('Без звука в выбранное время'),
            subtitle: const Text('Уведомления придут, но тихо'),
          ),
          if (prefs.hasQuietHours)
            Padding(
              padding: const EdgeInsets.only(right: 10, bottom: 4),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final picked = await _pick(context, from);
                        if (picked != null) onChanged(picked, to);
                      },
                      child: Text('С ${_label(from)}'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final picked = await _pick(context, to);
                        if (picked != null) onChanged(from, picked);
                      },
                      child: Text('До ${_label(to)}'),
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
