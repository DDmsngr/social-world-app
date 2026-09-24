import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/state_message.dart';
import '../../../core/widgets/sw_widgets.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../moderation/domain/entities/report_reason.dart';
import '../../moderation/presentation/providers/report_providers.dart';
import '../../moderation/presentation/widgets/report_sheet.dart';
import '../domain/entities/need_request.dart';
import 'providers/needs_providers.dart';
import 'widgets/need_widgets.dart';

/// Просьба «Мне надо» целиком: текст, отклики, действия автора.
class NeedDetailScreen extends ConsumerWidget {
  const NeedDetailScreen({super.key, required this.needId, this.need});

  final String needId;
  final NeedRequest? need;

  void _back(BuildContext context) =>
      context.canPop() ? context.pop() : context.go(Routes.home);

  Future<void> _onMenu(
    BuildContext context,
    WidgetRef ref,
    String value,
    NeedRequest need,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final actions = ref.read(needActionsProvider);
    switch (value) {
      case 'close':
        final error = await actions.close(need.id);
        messenger.showSnackBar(
          SnackBar(content: Text(error ?? 'Просьба закрыта — с карты она ушла')),
        );
      case 'delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Удалить просьбу?'),
            content: const Text('Вместе с ней удалятся и отклики.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Нет'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Удалить'),
              ),
            ],
          ),
        );
        if (ok != true) return;
        final error = await actions.delete(need.id);
        if (error != null) {
          messenger.showSnackBar(SnackBar(content: Text(error)));
        } else if (context.mounted) {
          _back(context);
        }
      case 'report':
        final sent = await showReportSheet(
          context,
          target: ReportTarget.need,
          targetId: need.id,
          authorId: need.authorId,
          subject: need.text,
        );
        if (!sent) return;
        ref.invalidate(pulseNeedsProvider);
        messenger.showSnackBar(const SnackBar(content: Text('Жалоба отправлена')));
        if (context.mounted) _back(context);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(needProvider(needId));
    final current = async.value ?? need;
    final me = ref.watch(currentUserProvider)?.id;
    final isAuthor = current != null && me == current.authorId;
    final hidden = ref.read(reportRepositoryProvider).hiddenTargetIds;

    Widget body;
    if (current != null && !hidden.contains(current.id)) {
      body = _Body(need: current, isAuthor: isAuthor);
    } else if (async.isLoading) {
      body = const LoadingView();
    } else if (async.hasError) {
      body = StateMessage.error(
        title: 'Просьба не загрузилась',
        onAction: () => ref.invalidate(needProvider(needId)),
      );
    } else {
      body = const StateMessage(
        title: 'Просьба недоступна',
        text: 'Её удалили или ссылка устарела.',
        icon: Icons.volunteer_activism_outlined,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Мне надо'),
        leading: IconButton(
          onPressed: () => _back(context),
          tooltip: 'Назад',
          icon: const Icon(Icons.arrow_back),
        ),
        actions: [
          if (current != null)
            PopupMenuButton<String>(
              tooltip: 'Действия',
              color: AppColors.ink2,
              onSelected: (value) => _onMenu(context, ref, value, current),
              itemBuilder: (_) => [
                if (isAuthor) ...[
                  if (current.isVisible)
                    const PopupMenuItem(value: 'close', child: Text('Вопрос решён')),
                  const PopupMenuItem(value: 'delete', child: Text('Удалить')),
                ] else
                  const PopupMenuItem(value: 'report', child: Text('Пожаловаться')),
              ],
            ),
        ],
      ),
      body: body,
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.need, required this.isAuthor});

  final NeedRequest need;
  final bool isAuthor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final responses = ref.watch(needResponsesProvider(need.id));

    return ListView(
      padding: AppSpacing.page(context),
      children: [
        SectionLabel(formatNeedExpiry(need)),
        const SizedBox(height: 12),
        Text(need.text, style: AppTypography.serif(28)),
        const SizedBox(height: 16),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: () => openProfile(context, need.authorId),
                borderRadius: BorderRadius.circular(8),
                child: Row(
                  children: [
                    UserAvatar(name: need.authorName, url: need.authorAvatarUrl, radius: 14),
                    const SizedBox(width: 10),
                    Expanded(child: Text(need.authorName)),
                    Icon(Icons.chevron_right, color: AppColors.textFaint),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.place_outlined, size: 17, color: AppColors.textFaint),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      need.placeTitle ??
                          'Примерный район — точное место не показывается',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        NeedRespondButton(need: need),
        if (isAuthor && need.isVisible) ...[
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final error = await ref.read(needActionsProvider).close(need.id);
              messenger.showSnackBar(
                SnackBar(content: Text(error ?? 'Просьба закрыта — с карты она ушла')),
              );
            },
            child: const Text('Вопрос решён'),
          ),
        ],
        const SizedBox(height: 26),
        const SectionLabel('Отклики'),
        const SizedBox(height: 12),
        responses.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Row(
            children: [
              const Expanded(child: Text('Отклики не загрузились')),
              TextButton(
                onPressed: () => ref.invalidate(needResponsesProvider(need.id)),
                child: const Text('Повторить'),
              ),
            ],
          ),
          data: (list) => list.isEmpty
              ? Text('Пока никто не откликнулся.', style: theme.textTheme.bodyMedium)
              : Column(
                  children: [
                    for (final r in list)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: UserAvatar(
                          name: r.authorName,
                          url: r.authorAvatarUrl,
                          radius: 18,
                        ),
                        title: Text(r.authorName),
                        subtitle: r.text == null ? null : Text(r.text!),
                        onTap: () => openProfile(context, r.authorId),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
