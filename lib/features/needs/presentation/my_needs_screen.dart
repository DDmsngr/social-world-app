import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/state_message.dart';
import '../../../core/widgets/sw_widgets.dart';
import 'providers/needs_providers.dart';
import 'widgets/need_widgets.dart';

/// Мои просьбы «Мне надо», включая закрытые.
class MyNeedsScreen extends ConsumerWidget {
  const MyNeedsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final needs = ref.watch(myNeedsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Мне надо'),
        actions: [
          IconButton(
            onPressed: () => context.push(Routes.createNeed),
            tooltip: 'Новая просьба',
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: needs.when(
        loading: () => const LoadingView(),
        error: (_, _) => StateMessage.error(onAction: () => ref.invalidate(myNeedsProvider)),
        data: (list) => list.isEmpty
            ? StateMessage(
                title: 'Просьб пока нет',
                text: 'Нужно повесить полку, найти попутчика или напарника '
                    'для тенниса? Попросите город.',
                icon: Icons.volunteer_activism_outlined,
                actionLabel: 'Попросить',
                onAction: () => context.push(Routes.createNeed),
              )
            : ListView.separated(
                padding: AppSpacing.page(context),
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, index) {
                  final need = list[index];
                  return GlassCard(
                    padding: const EdgeInsets.all(16),
                    onTap: () =>
                        context.push('${Routes.needDetail}/${need.id}', extra: need),
                    child: Row(
                      children: [
                        Icon(
                          Icons.volunteer_activism_outlined,
                          color: need.isVisible ? AppColors.primaryTint : AppColors.textFaint,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                need.text,
                                style: theme.textTheme.titleLarge,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${formatNeedExpiry(need)} · ${formatResponses(need.replyCount)}',
                                style: theme.textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right, color: AppColors.textFaint),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}
