import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/state_message.dart';
import '../../discover/presentation/providers/city_provider.dart';
import '../../notifications/notifications.dart';
import 'providers/feed_providers.dart';
import 'widgets/post_card.dart';
import 'widgets/story_strip.dart';

class FeedScreen extends ConsumerWidget {
  const FeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(feedProvider);
    final unread = ref.watch(unreadNotificationsProvider);
    final scope = ref.watch(feedScopeProvider);
    final cityName = ref.watch(cityProvider).name;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Flow'),
        actions: [
          IconButton(
            onPressed: () => context.push(Routes.notifications),
            tooltip: unread == 0 ? 'Уведомления' : 'Уведомления: $unread новых',
            icon: Badge(
              isLabelVisible: unread > 0,
              label: Text(unread > 9 ? '9+' : '$unread'),
              backgroundColor: AppColors.primary,
              textColor: AppColors.onPrimary,
              child: Icon(Icons.notifications_none, color: AppColors.textDim),
            ),
          ),
          IconButton(
            onPressed: () => ref.read(feedProvider.notifier).refresh(),
            tooltip: 'Обновить',
            icon: Icon(Icons.refresh, color: AppColors.textDim),
          ),
          const SizedBox(width: 8),
        ],
        // «Страна | Город» (п. 47). Город — тот же, что выбран на Pulse.
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 0, AppSpacing.gutter, 10),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<FeedScope>(
                showSelectedIcon: false,
                segments: [
                  for (final item in FeedScope.values)
                    ButtonSegment(
                      value: item,
                      label: Text(
                        item == FeedScope.city ? cityName : item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                selected: {scope},
                onSelectionChanged: (selected) =>
                    ref.read(feedScopeProvider.notifier).set(selected.first),
              ),
            ),
          ),
        ),
      ),
      body: feed.when(
        loading: () => const LoadingView(),
        error: (_, _) => StateMessage.error(
          label: 'Моменты',
          title: 'Моменты не загрузились',
          onAction: () => ref.read(feedProvider.notifier).refresh(),
        ),
        data: (posts) {
          if (posts.isEmpty) {
            return StateMessage(
              label: 'Моменты',
              title: 'Пока тихо',
              text: scope == FeedScope.city
                  ? 'В городе «$cityName» пока никто ничего не опубликовал. '
                        'Посмотрите всю страну или начните первым.'
                  : 'Здесь ещё никто ничего не опубликовал. '
                        'Начните первым — вкладка «Создать».',
              actionLabel: scope == FeedScope.city ? 'Вся страна' : null,
              onAction: scope == FeedScope.city
                  ? () => ref.read(feedScopeProvider.notifier).set(FeedScope.country)
                  : null,
            );
          }

          final stories = storiesFrom(posts);

          return RefreshIndicator(
            color: AppColors.primaryTint,
            backgroundColor: AppColors.ink2,
            onRefresh: () => ref.read(feedProvider.notifier).refresh(),
            child: ListView.builder(
              padding: const EdgeInsets.only(top: 8, bottom: 24),
              // +1 — полоса историй первым элементом.
              itemCount: posts.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: StoryStrip(stories: stories),
                  );
                }
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
                  child: PostCard(post: posts[index - 1]),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
