import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/app_typography.dart';
import '../widgets/sw_widgets.dart';
import 'update_controller.dart';

/// «Лампочка» обновления: круглая кнопка над нижней навигацией, которая
/// загорается, когда вышла новая версия, и показывает прогресс закачки.
/// Живёт в [Stack] поверх содержимого вкладок, поэтому видна из любой вкладки.
class UpdateBadge extends ConsumerWidget {
  const UpdateBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(updateControllerProvider);

    final hidden = state.stage == UpdateStage.idle ||
        state.stage == UpdateStage.checking ||
        state.stage == UpdateStage.upToDate;
    if (hidden) return const SizedBox.shrink();

    final (icon, color) = switch (state.stage) {
      UpdateStage.readyToInstall => (Icons.download_done, AppColors.success),
      UpdateStage.failed => (Icons.error_outline, AppColors.danger),
      _ => (Icons.system_update_alt, AppColors.primary),
    };

    return Positioned(
      right: AppSpacing.gutter,
      bottom: AppSpacing.gutter,
      child: Material(
        color: color,
        shape: const CircleBorder(),
        elevation: 6,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => showModalBottomSheet<void>(
            context: context,
            backgroundColor: Colors.transparent,
            builder: (_) => const _UpdateSheet(),
          ),
          child: SizedBox(
            width: 48,
            height: 48,
            child: state.stage == UpdateStage.downloading
                ? Padding(
                    padding: const EdgeInsets.all(13),
                    child: CircularProgressIndicator(
                      value: state.progress > 0 ? state.progress : null,
                      strokeWidth: 2.5,
                      color: AppColors.onPrimary,
                    ),
                  )
                : Icon(icon, color: AppColors.onPrimary),
          ),
        ),
      ),
    );
  }
}

class _UpdateSheet extends ConsumerWidget {
  const _UpdateSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(updateControllerProvider);
    final controller = ref.read(updateControllerProvider.notifier);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.gutter),
      child: SheetCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: SectionLabel('Обновление'),
            ),
            const SizedBox(height: 14),
            ..._body(context, state, controller),
          ],
        ),
      ),
    );
  }

  List<Widget> _body(
    BuildContext context,
    UpdateState state,
    UpdateController controller,
  ) {
    switch (state.stage) {
      case UpdateStage.available:
        final info = state.info!;
        return [
          Text('Версия ${info.versionName} уже вышла',
              style: AppTypography.serif(24)),
          const SizedBox(height: 10),
          Text(
            info.notes.isEmpty
                ? 'Свежая сборка Social World. Скачивание идёт в фоне — '
                    'приложением можно пользоваться дальше.'
                : info.notes,
            style: TextStyle(color: AppColors.textDim),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              controller.download();
            },
            child: const Text('Скачать'),
          ),
        ];

      case UpdateStage.downloading:
        return [
          Text('Скачиваем обновление', style: AppTypography.serif(24)),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: state.progress > 0 ? state.progress : null,
              minHeight: 6,
              backgroundColor: AppColors.hairStrong,
              color: AppColors.primaryTint,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '${(state.progress * 100).round()}% — окно можно закрыть, '
            'скачивание не прервётся.',
            style: TextStyle(color: AppColors.textDim),
          ),
        ];

      case UpdateStage.readyToInstall:
        return [
          Text('Обновление скачано', style: AppTypography.serif(24)),
          const SizedBox(height: 10),
          Text(
            'Обновить сейчас? Android покажет своё окно установки — '
            'там нужно подтвердить, дальше всё произойдёт само.',
            style: TextStyle(color: AppColors.textDim),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Потом'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    controller.install();
                  },
                  child: const Text('Сейчас'),
                ),
              ),
            ],
          ),
        ];

      case UpdateStage.failed:
        return [
          Text('Не получилось', style: AppTypography.serif(24)),
          const SizedBox(height: 10),
          Text(
            state.error ?? 'Неизвестная ошибка',
            style: TextStyle(color: AppColors.textDim),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              controller.download();
            },
            child: const Text('Попробовать снова'),
          ),
        ];

      case UpdateStage.idle:
      case UpdateStage.checking:
      case UpdateStage.upToDate:
        return const [SizedBox.shrink()];
    }
  }
}
