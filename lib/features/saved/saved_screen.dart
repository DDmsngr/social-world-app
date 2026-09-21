import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/links/deep_links.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/state_message.dart';
import '../../core/widgets/sw_widgets.dart';
import 'saved.dart';

/// Профиль → Сохранённое: посты, события, места и маршруты, которые человек
/// отложил. Состояние лежит на сервере, поэтому переживает перезапуск.
class SavedScreen extends ConsumerWidget {
  const SavedScreen({super.key});

  IconData _icon(SavedKind kind) => switch (kind) {
    SavedKind.post => Icons.article_outlined,
    SavedKind.event => Icons.event_outlined,
    SavedKind.place => Icons.place_outlined,
    SavedKind.route => Icons.timeline,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(savedItemsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Сохранённое'),
        leading: IconButton(
          onPressed: () =>
              context.canPop() ? context.pop() : context.go(Routes.profile),
          tooltip: 'Назад',
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: items.when(
        loading: () => const LoadingView(),
        error: (_, _) => StateMessage.error(
          onAction: () => ref.invalidate(savedItemsProvider),
        ),
        data: (list) {
          if (list.isEmpty) {
            return const StateMessage(
              title: 'Пока ничего нет',
              text: 'Сохраняйте посты, события, места и маршруты закладкой — '
                  'они соберутся здесь.',
              icon: Icons.bookmark_border,
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.refresh(savedItemsProvider.future),
            child: ListView.separated(
              padding: AppSpacing.page(context),
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = list[index];
                return GlassCard(
                  padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
                  onTap: () => context.push(
                    DeepLinks.locationFor(item.kind.link, item.id),
                  ),
                  child: Row(
                    children: [
                      Icon(_icon(item.kind), color: AppColors.primaryTint),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            Text(
                              [item.kind.label, ?item.subtitle].join(' · '),
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => ref
                            .read(savedProvider.notifier)
                            .toggle(item.kind, item.id),
                        tooltip: 'Убрать из сохранённого',
                        icon: Icon(Icons.bookmark, color: AppColors.primaryTint),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
