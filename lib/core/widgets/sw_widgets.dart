import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/app_typography.dart';

/// Мелкая подпись с чертой слева — тот же приём, что в секциях лендинга.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 26, height: 1, color: AppColors.textFaint),
        const SizedBox(width: 10),
        Text(text.toUpperCase(), style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.hair),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Карточка модального листа.
///
/// Отдельно от [GlassCard] именно из-за фона: у стеклянной карточки он
/// полупрозрачный, и поверх ленты сквозь лист читается чужой текст.
class SheetCard extends StatelessWidget {
  const SheetCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.ink2,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.hairStrong),
      ),
      child: child,
    );
  }
}

/// Пустой экран-заглушка для разделов, которые появятся в следующих фазах.
/// Держим их в навигации с первого дня, чтобы каркас был проходимым целиком.
class PhasePlaceholder extends StatelessWidget {
  const PhasePlaceholder({
    super.key,
    required this.title,
    required this.phase,
    required this.items,
  });

  final String title;
  final String phase;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.gutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionLabel(phase),
            const SizedBox(height: 14),
            Text(title, style: AppTypography.serif(32)),
            const SizedBox(height: 18),
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('— ', style: TextStyle(color: AppColors.clay)),
                    Expanded(
                      child: Text(
                        item,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
