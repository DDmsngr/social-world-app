import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/sheet_parts.dart';
import '../../../../core/widgets/sw_widgets.dart';
import '../../domain/entities/quest.dart';
import '../providers/quests_providers.dart';
import 'quest_action_panel.dart';
import 'quest_format.dart';

/// Карточка квеста поверх Pulse (п. 22): фото, название, место, участники,
/// главная кнопка по состоянию и «Подробнее».
Future<void> showQuestSheet(BuildContext context, Quest quest) =>
    showModalBottomSheet<void>(
      context: context, useRootNavigator: true,
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
          SheetKindHeader(kind: 'Квест', detail: formatQuestWhen(quest)),
          const SizedBox(height: 10),
          Text(quest.title, style: AppTypography.serif(26)),
          const SizedBox(height: 6),
          InkWell(
            onTap: () {
              Navigator.of(context).pop();
              openProfile(context, quest.authorId);
            },
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  UserAvatar(name: quest.authorName, url: quest.authorAvatarUrl, radius: 11),
                  const SizedBox(width: 8),
                  Text(
                    'Организатор · ${quest.authorName}',
                    style: TextStyle(color: AppColors.primaryTint, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          if (quest.description != null && quest.description!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              quest.description!.trim(),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ],
          const SizedBox(height: 10),
          if (quest.placeTitle != null)
            SheetFact(icon: Icons.place_outlined, text: quest.placeTitle!),
          SheetFact(icon: Icons.group_outlined, text: formatOccupancy(quest)),
          if (quest.extraInfo != null && quest.extraInfo!.trim().isNotEmpty)
            SheetFact(icon: Icons.info_outline, text: quest.extraInfo!.trim()),
          // «Подробнее» сразу под описанием, а не в самом низу за кнопками.
          SheetMoreLink(
            label: 'Подробнее о квесте →',
            onPressed: () {
              Navigator.of(context).pop();
              context.push('${Routes.questDetail}/${quest.id}', extra: quest);
            },
          ),
          const SizedBox(height: 8),
          QuestActionPanel(quest: quest, compact: true),
        ],
      ),
    );
  }
}
