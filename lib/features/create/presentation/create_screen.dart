import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../routes/presentation/providers/route_recorder.dart';
import 'compose_screen.dart';

/// Вкладка «+»: только выбор, что создать. Каждая карточка ведёт на свой
/// сфокусированный экран, где нет ничего лишнего. Раньше здесь была одна
/// длинная форма с переключателем видов, местом, настройками и кнопкой в
/// самом низу, и человек терялся, не успев начать.
class CreateScreen extends ConsumerWidget {
  const CreateScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recording = ref.watch(routeRecorderProvider).isActive;

    void open(String location) => context.push(location);

    final options = [
      _Option(
        icon: Icons.bolt_outlined,
        title: 'Момент',
        text: 'Пара слов, фото или видео о том, что рядом прямо сейчас',
        onTap: () => open('${Routes.compose}/${ComposeKind.moment.segment}'),
        primary: true,
      ),
      _Option(
        icon: Icons.article_outlined,
        title: 'Статья',
        text: 'Длинный текст с фото: обзор места, история, маршрут выходных',
        onTap: () => open('${Routes.compose}/${ComposeKind.article.segment}'),
      ),
      _Option(
        icon: Icons.timeline,
        title: 'Маршрут',
        text: 'Запишите путь по городу и поделитесь им с фото на карте',
        onTap: () => open(Routes.routeRecorder),
      ),
      _Option(
        icon: Icons.event_outlined,
        title: 'Событие',
        text: 'Соберите людей: дата, место, при желании маршрут',
        onTap: () => open('${Routes.compose}/${ComposeKind.event.segment}'),
      ),
      _Option(
        icon: Icons.flag_outlined,
        title: 'Квест',
        text: 'Задание или встреча со своими правилами и заявками',
        onTap: () => open(Routes.createQuest),
      ),
      _Option(
        icon: Icons.volunteer_activism_outlined,
        title: 'Мне надо',
        text: 'Попросите помощи у тех, кто рядом',
        onTap: () => open(Routes.createNeed),
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Создать')),
      body: ListView(
        padding: AppSpacing.page(context, top: AppSpacing.gutter),
        children: [
          Semantics(
            header: true,
            child: Text('Что создаём?', style: AppTypography.serif(32)),
          ),
          const SizedBox(height: 16),
          // Запись маршрута может идти свёрнутой: напоминаем о ней сверху, чтобы
          // не начинать вторую.
          if (recording) ...[
            _RecordingCard(onTap: () => open(Routes.routeRecorder)),
            const SizedBox(height: 12),
          ],
          for (final option in options) ...[
            option,
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.icon,
    required this.title,
    required this.text,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String title;
  final String text;
  final VoidCallback onTap;

  /// Самое частое действие выделено цветом: оно же первое под рукой.
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final background = primary ? AppColors.primary : AppColors.card;
    final foreground = primary ? AppColors.onPrimary : AppColors.text;
    final secondary = primary ? AppColors.onPrimary.withValues(alpha: 0.82) : AppColors.textDim;
    return Semantics(
      button: true,
      label: '$title. $text',
      excludeSemantics: true,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: Container(
            constraints: const BoxConstraints(minHeight: 76),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: primary ? null : Border.all(color: AppColors.hair),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: primary
                        ? AppColors.onPrimary.withValues(alpha: 0.18)
                        : AppColors.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: primary ? AppColors.onPrimary : AppColors.primaryTint),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: foreground),
                      ),
                      const SizedBox(height: 2),
                      Text(text, style: TextStyle(fontSize: 13, height: 1.3, color: secondary)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right, color: secondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecordingCard extends StatelessWidget {
  const _RecordingCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primary.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(Icons.fiber_manual_record, size: 14, color: AppColors.primaryTint),
              const SizedBox(width: 12),
              const Expanded(child: Text('Идёт запись маршрута')),
              Text(
                'К записи',
                style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.primaryTint),
              ),
              Icon(Icons.chevron_right, color: AppColors.primaryTint),
            ],
          ),
        ),
      ),
    );
  }
}
