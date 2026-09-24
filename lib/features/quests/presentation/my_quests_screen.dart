import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/state_message.dart';
import '../../../core/widgets/sw_widgets.dart';
import '../domain/entities/quest.dart';
import 'providers/quests_providers.dart';
import 'widgets/quest_format.dart';

/// «🎯 Квесты» (п. 43). Виден только самому человеку: чужие активные
/// квесты не показываются нигде (п. 44) — сервер отдаёт только свои.
class MyQuestsScreen extends StatelessWidget {
  const MyQuestsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: MyQuestsTab.values.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Квесты'),
          actions: [
            IconButton(
              onPressed: () => context.push(Routes.createQuest),
              tooltip: 'Создать квест',
              icon: const Icon(Icons.add),
            ),
          ],
          bottom: TabBar(
            tabs: [for (final tab in MyQuestsTab.values) Tab(text: tab.label)],
          ),
        ),
        body: TabBarView(
          children: [for (final tab in MyQuestsTab.values) _QuestList(tab: tab)],
        ),
      ),
    );
  }
}

class _QuestList extends ConsumerWidget {
  const _QuestList({required this.tab});

  final MyQuestsTab tab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quests = ref.watch(myQuestsProvider(tab));

    return quests.when(
      loading: () => const LoadingView(),
      error: (_, _) => StateMessage.error(
        onAction: () => ref.invalidate(myQuestsProvider(tab)),
      ),
      data: (list) {
        if (list.isEmpty) {
          return StateMessage(
            title: switch (tab) {
              MyQuestsTab.active => 'Активных квестов нет',
              MyQuestsTab.history => 'История пуста',
              MyQuestsTab.authored => 'Вы ещё не создавали квестов',
            },
            text: switch (tab) {
              MyQuestsTab.active => 'Найдите квест на Pulse и подайте заявку.',
              MyQuestsTab.history => 'Здесь появятся квесты, в которых вы участвовали.',
              MyQuestsTab.authored =>
                'Прогулка, игра, кофе в вашем заведении — позовите людей.',
            },
            icon: Icons.flag_outlined,
            actionLabel: tab == MyQuestsTab.authored ? 'Создать квест' : null,
            onAction: tab == MyQuestsTab.authored
                ? () => context.push(Routes.createQuest)
                : null,
          );
        }
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(myQuestsProvider(tab));
            await ref.read(myQuestsProvider(tab).future);
          },
          child: ListView.separated(
            padding: AppSpacing.page(context),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (_, index) => QuestTile(quest: list[index]),
          ),
        );
      },
    );
  }
}

/// Строка квеста в списках профиля.
class QuestTile extends StatelessWidget {
  const QuestTile({super.key, required this.quest});

  final Quest quest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = quest.myStatus;

    return GlassCard(
      padding: const EdgeInsets.all(16),
      onTap: () => context.push('${Routes.questDetail}/${quest.id}', extra: quest),
      child: Row(
        children: [
          Icon(Icons.flag_outlined, color: AppColors.primaryTint),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  quest.title,
                  style: theme.textTheme.titleLarge,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    formatQuestWhen(quest),
                    formatOccupancy(quest),
                    if (status != null) status.label,
                  ].join(' · '),
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: AppColors.textFaint),
        ],
      ),
    );
  }
}
