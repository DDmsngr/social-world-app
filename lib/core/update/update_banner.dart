import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_colors.dart';
import 'update_controller.dart';

/// Плашка над нижней панелью, когда новая версия скачана: одно нажатие —
/// и открывается системное «Обновить приложение?». Крестик прячет её до
/// следующего запуска; в настройках строка «Обновление готово» остаётся.
class UpdateReadyBanner extends ConsumerWidget {
  const UpdateReadyBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(updateControllerProvider);
    final controller = ref.read(updateControllerProvider.notifier);
    if (state.stage != UpdateStage.readyToInstall || controller.bannerDismissed) {
      return const SizedBox.shrink();
    }
    final green = AppColors.success;
    return Material(
      color: AppColors.ink2,
      elevation: 6,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: controller.install,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: green, width: 1.2),
          ),
          child: Row(
            children: [
              Icon(Icons.system_update_alt, color: green),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Новая версия ChaWo скачана', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
              TextButton(
                onPressed: controller.install,
                child: Text('Установить', style: TextStyle(color: green, fontWeight: FontWeight.w600)),
              ),
              IconButton(
                tooltip: 'Позже',
                onPressed: controller.dismissBanner,
                icon: Icon(Icons.close, size: 20, color: AppColors.textDim),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
