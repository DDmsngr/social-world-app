import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/state_message.dart';
import '../data/post_drafts.dart';

/// Список черновиков момента и статьи: тап открывает редактор с тем, что
/// было, смахивание или корзина удаляют.
class DraftsScreen extends ConsumerWidget {
  const DraftsScreen({super.key});

  String _when(DateTime at) {
    final now = DateTime.now();
    final hh = at.hour.toString().padLeft(2, '0');
    final mm = at.minute.toString().padLeft(2, '0');
    if (at.year == now.year && at.month == now.month && at.day == now.day) return 'сегодня, $hh:$mm';
    final dd = at.day.toString().padLeft(2, '0');
    final mo = at.month.toString().padLeft(2, '0');
    return '$dd.$mo, $hh:$mm';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drafts = ref.watch(postDraftsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Черновики')),
      body: drafts.when(
        loading: () => const LoadingView(),
        error: (_, _) => StateMessage.error(onAction: () => ref.invalidate(postDraftsProvider)),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Text('Черновиков нет', style: Theme.of(context).textTheme.bodyMedium),
            );
          }
          return ListView.separated(
            padding: AppSpacing.page(context, top: AppSpacing.gutter),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final draft = items[index];
              return Dismissible(
                key: ValueKey(draft.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(AppRadius.card),
                  ),
                  child: Icon(Icons.delete_outline, color: AppColors.danger),
                ),
                onDismissed: (_) async {
                  await PostDrafts.delete(draft.id);
                  ref.invalidate(postDraftsProvider);
                },
                child: Material(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    onTap: () async {
                      await context.push('${Routes.compose}/${draft.kind}', extra: draft);
                      ref.invalidate(postDraftsProvider);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppRadius.card),
                        border: Border.all(color: AppColors.hair),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            draft.isArticle ? Icons.article_outlined : Icons.bolt_outlined,
                            color: AppColors.primaryTint,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(draft.label, maxLines: 2, overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 2),
                                Text(
                                  '${draft.isArticle ? 'Статья' : 'Момент'} · ${_when(draft.updatedAt)}',
                                  style: TextStyle(fontSize: 12, color: AppColors.textDim),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Удалить черновик',
                            icon: Icon(Icons.delete_outline, color: AppColors.textDim),
                            onPressed: () async {
                              await PostDrafts.delete(draft.id);
                              ref.invalidate(postDraftsProvider);
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
