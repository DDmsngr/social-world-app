import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/app_typography.dart';
import 'sw_widgets.dart';

/// Единый вид «пусто» и «ошибка» для экранов. Загрузка, пустота и сбой должны
/// выглядеть по-разному и у каждого — понятный следующий шаг: без пустого
/// экрана без объяснения и без ошибки без кнопки «Повторить».
class StateMessage extends StatelessWidget {
  const StateMessage({
    super.key,
    required this.title,
    this.text,
    this.label,
    this.icon,
    this.actionLabel,
    this.onAction,
  });

  /// Ошибка загрузки с повтором — самый частый случай.
  const StateMessage.error({
    super.key,
    this.title = 'Не удалось загрузить',
    this.text = 'Проверьте соединение и попробуйте ещё раз.',
    this.label,
    this.icon = Icons.cloud_off_outlined,
    this.actionLabel = 'Повторить',
    required VoidCallback this.onAction,
  });

  final String title;
  final String? text;
  final String? label;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.gutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (label != null) ...[
              SectionLabel(label!),
              const SizedBox(height: 14),
            ],
            if (icon != null) ...[
              Icon(icon, size: 28, color: Theme.of(context).hintColor),
              const SizedBox(height: 12),
            ],
            Text(title, style: AppTypography.serif(28)),
            if (text != null) ...[
              const SizedBox(height: 10),
              Text(text!, style: Theme.of(context).textTheme.bodyMedium),
            ],
            if (onAction != null) ...[
              const SizedBox(height: 18),
              FilledButton(
                onPressed: onAction,
                child: Text(actionLabel ?? 'Повторить'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Спиннер по центру — единственное место, где рисуется индикатор загрузки
/// целого экрана.
class LoadingView extends StatelessWidget {
  const LoadingView({super.key});

  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator());
}
