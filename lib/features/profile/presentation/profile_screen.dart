import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/sw_widgets.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../feed/presentation/providers/feed_providers.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Профиль')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.gutter),
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: AppColors.card,
                child: Text(
                  (user?.displayName ?? '?').characters.first.toUpperCase(),
                  style: AppTypography.serif(28, color: AppColors.primaryTint),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user?.displayName ?? 'Без имени',
                      style: AppTypography.serif(26),
                    ),
                    if (user?.displayContact != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        user!.displayContact!,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          GlassCard(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Social Score'),
                Text(
                  '${user?.socialScore ?? 0}',
                  style: AppTypography.serif(24, color: AppColors.success),
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          const _MyPosts(),
          const SizedBox(height: 24),
          const PhaseList(),
          const SizedBox(height: 24),
          TextButton(
            onPressed: () => ref.read(authRepositoryProvider).signOut(),
            child: const Text('Выйти'),
          ),
        ],
      ),
    );
  }
}

class _MyPosts extends ConsumerWidget {
  const _MyPosts();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posts = ref.watch(myPostsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('Публикации'),
        const SizedBox(height: 12),
        posts.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, _) => Text(
            'Не удалось загрузить публикации',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          data: (items) {
            if (items.isEmpty) {
              return Text(
                'Вы ещё ничего не опубликовали.',
                style: Theme.of(context).textTheme.bodyMedium,
              );
            }
            return Column(
              children: [
                for (final post in items)
                  GlassCard(
                    padding: const EdgeInsets.all(14),
                    // Маршрут в списке публикаций — это строка с названием,
                    // и без перехода открыть свою же прогулку было бы негде.
                    onTap: post.isRoute
                        ? () => context.push('${Routes.routes}/${post.routeId}')
                        : null,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          post.body ?? 'Публикация',
                          style: Theme.of(context).textTheme.bodyLarge,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              post.isRoute
                                  ? Icons.timeline
                                  : Icons.favorite_border,
                              size: 15,
                              color: post.isRoute
                                  ? AppColors.primaryTint
                                  : AppColors.textFaint,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${post.likeCount}',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(fontSize: 12),
                            ),
                            if (post.placeTitle != null) ...[
                              const SizedBox(width: 12),
                              Flexible(
                                child: Text(
                                  post.placeTitle!,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(fontSize: 12),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class PhaseList extends StatelessWidget {
  const PhaseList({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        SectionLabel('Дальше'),
        SizedBox(height: 12),
        _Row('Настройки приватности геолокации', 'Фаза 2'),
        _Row('Список заблокированных', 'Фаза 2'),
        _Row('События и push', 'Фаза 3'),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.title, this.phase);

  final String title;
  final String phase;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: Theme.of(context).textTheme.bodyLarge),
          Text(
            phase,
            style: const TextStyle(fontSize: 12, color: AppColors.textFaint),
          ),
        ],
      ),
    );
  }
}
