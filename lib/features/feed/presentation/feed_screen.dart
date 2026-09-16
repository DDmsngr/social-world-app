import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/sw_widgets.dart';
import '../../moderation/domain/entities/report_reason.dart';
import '../../moderation/presentation/widgets/report_sheet.dart';
import 'providers/feed_providers.dart';
import 'widgets/post_card.dart';

class FeedScreen extends ConsumerWidget {
  const FeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(feedProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Сочи'),
        actions: [
          IconButton(
            onPressed: () => ref.read(feedProvider.notifier).refresh(),
            tooltip: 'Обновить',
            icon: const Icon(Icons.refresh, color: AppColors.textDim),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: feed.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => _FeedMessage(
          title: 'Лента не загрузилась',
          text: 'Проверьте соединение и попробуйте ещё раз.',
          actionLabel: 'Повторить',
          onAction: () => ref.read(feedProvider.notifier).refresh(),
        ),
        data: (posts) {
          if (posts.isEmpty) {
            return const _FeedMessage(
              title: 'Пока тихо',
              text: 'В городе ещё никто ничего не опубликовал. '
                  'Начните первым — вкладка «Создать».',
            );
          }

          return RefreshIndicator(
            color: AppColors.primaryTint,
            backgroundColor: AppColors.ink2,
            onRefresh: () => ref.read(feedProvider.notifier).refresh(),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.gutter,
                12,
                AppSpacing.gutter,
                24,
              ),
              itemCount: posts.length,
              itemBuilder: (context, index) {
                final post = posts[index];
                return PostCard(
                  post: post,
                  onLike: () => ref.read(feedProvider.notifier).toggleLike(post),
                  onReport: () async {
                    final sent = await showReportSheet(
                      context,
                      target: ReportTarget.post,
                      targetId: post.id,
                      subject: '${post.authorName}: ${post.body ?? 'публикация'}',
                    );
                    if (!sent || !context.mounted) return;
                    ref.read(feedProvider.notifier).hide(post.id);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Жалоба отправлена')),
                    );
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _FeedMessage extends StatelessWidget {
  const _FeedMessage({
    required this.title,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.gutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionLabel('Лента'),
            const SizedBox(height: 14),
            Text(title, style: AppTypography.serif(30)),
            const SizedBox(height: 10),
            Text(text, style: Theme.of(context).textTheme.bodyMedium),
            if (actionLabel != null) ...[
              const SizedBox(height: 18),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
