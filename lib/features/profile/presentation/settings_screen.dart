import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_choice.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/update/update_controller.dart';
import '../../../core/widgets/sw_widgets.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../discover/presentation/providers/discover_providers.dart';
import '../../discover/presentation/providers/presence_publisher.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  int? _pendingBlur;
  var _savingBlur = false;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final blur = (_pendingBlur ?? user?.locationBlurM ?? 500).toDouble();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Настройки'),
        leading: IconButton(
          onPressed: () =>
              context.canPop() ? context.pop() : context.go(Routes.profile),
          tooltip: 'Назад',
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.gutter),
        children: [
          const SectionLabel('Оформление'),
          const SizedBox(height: 12),
          const _ThemePicker(),
          const SizedBox(height: 26),
          const SectionLabel('Приватность'),
          const SizedBox(height: 12),
          const _PresenceSwitch(),
          const SizedBox(height: 10),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Радиус видимости на карте',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  'Насколько крупным будет это пятно. С маршрутом прогулки '
                  'иначе: если вы публикуете его сами, путь и точки съёмки '
                  'видны точно — это осознанная публикация, а не слежение.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                Slider(
                  value: blur.clamp(200, 2000),
                  min: 200,
                  max: 2000,
                  divisions: 18,
                  label: '${blur.round()} м',
                  activeColor: AppColors.primaryTint,
                  onChanged: (value) =>
                      setState(() => _pendingBlur = value.round()),
                  onChangeEnd: (value) async {
                    setState(() => _savingBlur = true);
                    try {
                      await ref
                          .read(authRepositoryProvider)
                          .updateLocationBlur(value.round());
                    } finally {
                      if (mounted) setState(() => _savingBlur = false);
                    }
                  },
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${blur.round()} м',
                      style: AppTypography.serif(20, color: AppColors.primaryTint),
                    ),
                    if (_savingBlur)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          const SectionLabel('Приложение'),
          const SizedBox(height: 12),
          const _UpdateRow(),
          const SizedBox(height: 10),
          const _VersionRow(),
          const SizedBox(height: 26),
          const SectionLabel('Аккаунт'),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () async {
              // Сначала убираем точку: после signOut сессии уже нет и удалить
              // свою строку в `locations` будет нечем — человек остался бы
              // висеть на чужих картах до протухания через два часа.
              try {
                await ref.read(discoverRepositoryProvider).clearPresence();
              } catch (_) {
                // Не повод не дать выйти из аккаунта.
              }
              await ref.read(authRepositoryProvider).signOut();
            },
            child: const Text('Выйти'),
          ),
        ],
      ),
    );
  }
}

class _PresenceSwitch extends ConsumerWidget {
  const _PresenceSwitch();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(presenceEnabledProvider);

    return GlassCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Показывать меня на карте',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  enabled
                      ? 'Пока приложение открыто, другие видят размытое пятно '
                            'вашего района. Выключите — точка исчезнет с карты '
                            'сразу.'
                      : 'Вас не видно в разделе «Рядом». Карта, события и '
                            'публикации работают как обычно.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch(
            value: enabled,
            activeThumbColor: AppColors.onPrimary,
            activeTrackColor: AppColors.primary,
            onChanged: (value) =>
                ref.read(presenceEnabledProvider.notifier).set(value),
          ),
        ],
      ),
    );
  }
}

class _ThemePicker extends ConsumerWidget {
  const _ThemePicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(themeChoiceProvider);

    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          for (final choice in ThemeChoice.values)
            Semantics(
              button: true,
              selected: choice == current,
              inMutuallyExclusiveGroup: true,
              child: InkWell(
                onTap: () =>
                    ref.read(themeChoiceProvider.notifier).choose(choice),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(choice.label),
                            if (choice.hint != null)
                              Text(
                                choice.hint!,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textDim,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (choice == current)
                        Icon(Icons.check, color: AppColors.primaryTint),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _VersionRow extends StatelessWidget {
  const _VersionRow();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final info = snapshot.data;
        return GlassCard(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Версия'),
              Text(
                info == null
                    ? '…'
                    : '${info.version} (${info.buildNumber})',
                style: TextStyle(color: AppColors.textDim),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _UpdateRow extends ConsumerWidget {
  const _UpdateRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(updateControllerProvider);
    final label = switch (state.stage) {
      UpdateStage.checking => 'Проверяем…',
      UpdateStage.available => 'Доступно обновление',
      UpdateStage.downloading => 'Скачивается…',
      UpdateStage.readyToInstall => 'Готово к установке',
      UpdateStage.failed => 'Не удалось проверить',
      _ => 'Вы используете последнюю версию',
    };

    return GlassCard(
      onTap: state.stage == UpdateStage.downloading
          ? null
          : () => ref
                .read(updateControllerProvider.notifier)
                .check(silent: false),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Обновления'),
          Text(label, style: TextStyle(color: AppColors.textDim)),
        ],
      ),
    );
  }
}
