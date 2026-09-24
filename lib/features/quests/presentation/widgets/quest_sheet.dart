import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/sw_widgets.dart';
import '../../domain/entities/quest.dart';
import '../providers/quests_providers.dart';
import 'quest_action_panel.dart';
import 'quest_format.dart';

/// Карточка квеста поверх Pulse (п. 22): фото, название, место, участники,
/// главная кнопка по состоянию и «Подробнее».
Future<void> showQuestSheet(BuildContext context, Quest quest) =>
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(AppSpacing.gutter),
        child: SheetCard(child: _QuestSheet(fallback: quest)),
      ),
    );

class _QuestSheet extends ConsumerWidget {
  const _QuestSheet({required this.fallback});

  final Quest fallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Свежая версия с сервера: после «Подать заявку» кнопка и счётчик
    // меняются прямо здесь, без перезагрузки карты.
    final quest = ref.watch(questProvider(fallback.id)).value ?? fallback;
    final theme = Theme.of(context);

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (quest.photoUrl != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.field),
              child: AspectRatio(
                aspectRatio: 16 / 8,
                child: CachedNetworkImage(
                  imageUrl: quest.photoUrl!,
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) => ColoredBox(color: AppColors.ink2),
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],
          SectionLabel(formatQuestWhen(quest)),
          const SizedBox(height: 10),
          Text(quest.title, style: AppTypography.serif(26)),
          const SizedBox(height: 8),
          if (quest.placeTitle != null)
            Text('📍 ${quest.placeTitle}', style: theme.textTheme.bodyMedium),
          Text(formatOccupancy(quest), style: theme.textTheme.bodyMedium),
          const SizedBox(height: 16),
          QuestActionPanel(quest: quest, compact: true),
          const SizedBox(height: 4),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              context.push('${Routes.questDetail}/${quest.id}', extra: quest);
            },
            child: const Text('Подробнее'),
          ),
        ],
      ),
    );
  }
}
