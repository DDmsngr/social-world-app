import 'package:cached_network_image/cached_network_image.dart';
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
import '../../feed/presentation/post_actions.dart';
import '../../moderation/domain/entities/report_reason.dart';
import '../../moderation/presentation/providers/report_providers.dart';
import '../../moderation/presentation/widgets/report_sheet.dart';
import '../../profile/domain/profile_models.dart';
import '../domain/entities/quest.dart';
import 'providers/quests_providers.dart';
import 'widgets/quest_action_panel.dart';
import 'widgets/quest_format.dart';

/// Полная карточка квеста. Данные всегда свежие с сервера: счётчик мест и
/// статус участия меняются от действий других людей.
///
/// [arrivalCode] приходит из QR (`socialworld://quest/<id>?arrive=<код>`):
/// экран сам отмечает прибытие — навести камеру и есть «отсканировать».
class QuestDetailScreen extends ConsumerStatefulWidget {
  const QuestDetailScreen({
    super.key,
    required this.questId,
    this.quest,
    this.arrivalCode,
  });

  final String questId;
  final Quest? quest;
  final String? arrivalCode;

  @override
  ConsumerState<QuestDetailScreen> createState() => _QuestDetailScreenState();
}

class _QuestDetailScreenState extends ConsumerState<QuestDetailScreen> {
  @override
  void initState() {
    super.initState();
    final code = widget.arrivalCode;
    if (code != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _arriveByQr(code));
    }
  }

  Future<void> _arriveByQr(String code) async {
    final messenger = ScaffoldMessenger.of(context);
    final error = await ref
        .read(questActionsProvider)
        .confirmArrival(widget.questId, code);
    messenger.showSnackBar(
      SnackBar(content: Text(error ?? 'Вы на месте. Хорошего квеста!')),
    );
  }

  void _back() => context.canPop() ? context.pop() : context.go(Routes.home);

  Future<void> _onMenu(String value, Quest quest) async {
    switch (value) {
      case 'cancel':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Отменить квест?'),
            content: const Text(
              'Участникам и заявителям придёт уведомление об отмене.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Нет'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Отменить квест'),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        final error = await ref.read(questActionsProvider).cancel(quest.id);
        messenger.showSnackBar(SnackBar(content: Text(error ?? 'Квест отменён')));
      case 'report':
        await _report(quest);
      case 'mute' || 'block':
        await blockAuthor(
          context,
          ref,
          userId: quest.authorId,
          name: quest.authorName,
          avatarUrl: quest.authorAvatarUrl,
          kind: value == 'block' ? BlockKind.block : BlockKind.mute,
        );
        ref.invalidate(pulseQuestsProvider);
    }
  }

  Future<void> _report(Quest quest) async {
    final sent = await showReportSheet(
      context,
      target: ReportTarget.quest,
      targetId: quest.id,
      authorId: quest.authorId,
      subject: quest.title,
    );
    if (!sent || !mounted) return;
    ref.invalidate(pulseQuestsProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Жалоба отправлена')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(questProvider(widget.questId));
    final quest = async.value ?? widget.quest;
    final me = ref.watch(currentUserProvider)?.id;
    final isAuthor = quest != null && me == quest.authorId;
    // Пожаловался — квест исчезает для этого человека сразу (п. 51).
    final hidden = ref.read(reportRepositoryProvider).hiddenTargetIds;

    Widget body;
    if (quest != null && !hidden.contains(quest.id)) {
      body = _Body(quest: quest, isAuthor: isAuthor, onReport: () => _report(quest));
    } else if (async.isLoading) {
      body = const LoadingView();
    } else if (async.hasError) {
      body = StateMessage.error(
        title: 'Квест не загрузился',
        onAction: () => ref.invalidate(questProvider(widget.questId)),
      );
    } else {
      body = const StateMessage(
        title: 'Квест недоступен',
        text: 'Он удалён, скрыт или ссылка устарела.',
        icon: Icons.flag_outlined,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Квест'),
        leading: IconButton(
          onPressed: _back,
          tooltip: 'Назад',
          icon: const Icon(Icons.arrow_back),
        ),
        actions: [
          if (quest != null)
            PopupMenuButton<String>(
              tooltip: 'Действия',
              color: AppColors.ink2,
              onSelected: (value) => _onMenu(value, quest),
              itemBuilder: (_) => [
                if (isAuthor) ...[
                  if (quest.isActive)
                    const PopupMenuItem(value: 'cancel', child: Text('Отменить квест')),
                ] else ...const [
                  PopupMenuItem(value: 'report', child: Text('Сообщить о проблеме')),
                  PopupMenuItem(value: 'mute', child: Text('Скрыть организатора')),
                  PopupMenuItem(value: 'block', child: Text('Заблокировать организатора')),
                ],
              ],
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref
            ..invalidate(questProvider(widget.questId))
            ..invalidate(questParticipantsProvider(widget.questId))
            ..invalidate(questMomentsProvider(widget.questId));
          await ref.read(questProvider(widget.questId).future);
        },
        child: body,
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.quest, required this.isAuthor, required this.onReport});

  final Quest quest;
  final bool isAuthor;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final holdsSlot = quest.myStatus?.holdsSlot ?? false;

    return ListView(
      padding: AppSpacing.page(context),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        if (quest.photoUrl != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.card),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: CachedNetworkImage(
                imageUrl: quest.photoUrl!,
                fit: BoxFit.cover,
                placeholder: (_, _) => ColoredBox(color: AppColors.ink2),
                errorWidget: (_, _, _) => ColoredBox(color: AppColors.ink2),
              ),
            ),
          ),
          const SizedBox(height: 18),
        ],
        SectionLabel(formatQuestWhen(quest)),
        const SizedBox(height: 12),
        Text(quest.title, style: AppTypography.serif(30)),
        if (quest.description != null) ...[
          const SizedBox(height: 14),
          Text(quest.description!, style: theme.textTheme.bodyLarge),
        ],
        const SizedBox(height: 20),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: () => openProfile(context, quest.authorId),
                borderRadius: BorderRadius.circular(8),
                child: Row(
                  children: [
                    UserAvatar(
                      name: quest.authorName,
                      url: quest.authorAvatarUrl,
                      radius: 14,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Организатор: ${quest.authorName}',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    Icon(Icons.chevron_right, color: AppColors.textFaint),
                  ],
                ),
              ),
              if (quest.placeTitle != null) ...[
                const SizedBox(height: 10),
                _InfoRow(icon: Icons.place_outlined, text: quest.placeTitle!),
              ],
              const SizedBox(height: 10),
              _InfoRow(icon: Icons.groups_outlined, text: formatOccupancy(quest)),
              if (quest.extraInfo != null) ...[
                const SizedBox(height: 10),
                _InfoRow(icon: Icons.info_outline, text: quest.extraInfo!),
              ],
            ],
          ),
        ),
        const SizedBox(height: 22),
        QuestActionPanel(quest: quest),
        if (!isAuthor)
          Center(
            child: TextButton.icon(
              onPressed: onReport,
              icon: Icon(Icons.report_gmailerrorred, size: 18, color: AppColors.textDim),
              label: Text(
                'Сообщить о проблеме',
                style: TextStyle(color: AppColors.textDim),
              ),
            ),
          ),
        if (isAuthor) ...[
          const SizedBox(height: 26),
          _OrganizerSection(quest: quest),
        ] else if (holdsSlot) ...[
          const SizedBox(height: 26),
          _Companions(questId: quest.id),
        ],
        const SizedBox(height: 26),
        _MomentsSection(questId: quest.id),
      ],
    );
  }
}

/// Заявки и участники — только у организатора (п. 26): у заявителя видны
/// очки активности, это не рейтинг качества человека (п. 27, 28).
class _OrganizerSection extends ConsumerWidget {
  const _OrganizerSection({required this.quest});

  final Quest quest;

  Future<void> _act(
    BuildContext context,
    Future<String?> Function() action,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final error = await action();
    if (error != null) messenger.showSnackBar(SnackBar(content: Text(error)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final participants = ref.watch(questParticipantsProvider(quest.id));
    final actions = ref.read(questActionsProvider);

    return participants.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => Row(
        children: [
          const Expanded(child: Text('Заявки не загрузились')),
          TextButton(
            onPressed: () => ref.invalidate(questParticipantsProvider(quest.id)),
            child: const Text('Повторить'),
          ),
        ],
      ),
      data: (list) {
        final requests = [
          for (final p in list)
            if (p.status == QuestParticipationStatus.requested) p,
        ];
        final members = [for (final p in list) if (p.status.holdsSlot) p];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionLabel('Заявки · ${requests.length}'),
            const SizedBox(height: 12),
            if (requests.isEmpty)
              Text(
                quest.needsApproval
                    ? 'Новых заявок нет.'
                    : 'Квест без лимита — люди присоединяются сразу, без заявок.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            for (final p in requests)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GlassCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _PersonRow(person: p, trailing: '🏆 ${p.socialScore} очков'),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton(
                              onPressed: quest.isFull
                                  ? null
                                  : () => _act(
                                      context,
                                      () => actions.decide(quest.id, p.id, approve: true),
                                    ),
                              child: const Text('Принять'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => _act(
                                context,
                                () => actions.decide(quest.id, p.id, approve: false),
                              ),
                              child: const Text('Отклонить'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 18),
            SectionLabel('Участники · ${quest.occupancy}'),
            const SizedBox(height: 12),
            if (members.isEmpty)
              Text(
                'Пока никого.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            for (final p in members)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _PersonRow(
                  person: p,
                  trailing: p.status == QuestParticipationStatus.arrived
                      ? 'на месте'
                      : null,
                  menu: PopupMenuButton<String>(
                    tooltip: 'Действия',
                    color: AppColors.ink2,
                    onSelected: (_) async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: Text('Исключить ${p.displayName}?'),
                          content: const Text(
                            'Человек выйдет из квеста и из квест-чата.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Нет'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Исключить'),
                            ),
                          ],
                        ),
                      );
                      if (ok == true && context.mounted) {
                        await _act(context, () => actions.remove(quest.id, p.id));
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'remove', child: Text('Исключить')),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Соучастники — одобренный участник видит тех, с кем он в квесте (они и
/// так вместе в квест-чате). Посторонним список не показывается (п. 44).
class _Companions extends ConsumerWidget {
  const _Companions({required this.questId});

  final String questId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(questParticipantsProvider(questId)).value ?? const [];
    if (list.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('Кто участвует'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in list)
              ActionChip(
                avatar: UserAvatar(name: p.displayName, url: p.avatarUrl, radius: 11),
                label: Text(p.displayName),
                onPressed: () => openProfile(context, p.profileId),
                backgroundColor: AppColors.card,
                side: BorderSide(color: AppColors.hair),
              ),
          ],
        ),
      ],
    );
  }
}

/// Социальная история квеста (п. 40): кто сам опубликовал Moment, по
/// времени. Это не список участников.
class _MomentsSection extends ConsumerWidget {
  const _MomentsSection({required this.questId});

  final String questId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final moments = ref.watch(questMomentsProvider(questId)).value ?? const [];
    if (moments.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('Моменты квеста'),
        const SizedBox(height: 12),
        for (final m in moments)
          InkWell(
            onTap: () => context.push('${Routes.posts}/${m.postId}'),
            borderRadius: BorderRadius.circular(AppRadius.field),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 54,
                    child: Text(
                      _hhmm(m.createdAt),
                      style: TextStyle(color: AppColors.textDim, fontSize: 13),
                    ),
                  ),
                  UserAvatar(name: m.authorName, url: m.authorAvatarUrl, radius: 14),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      m.body == null || m.body!.isEmpty
                          ? m.authorName
                          : '${m.authorName} — ${m.body}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (m.photoUrl != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: m.photoUrl!,
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                        errorWidget: (_, _, _) => const SizedBox(width: 44, height: 44),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  static String _hhmm(DateTime time) {
    final local = time.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({required this.person, this.trailing, this.menu});

  final QuestParticipation person;
  final String? trailing;
  final Widget? menu;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        InkWell(
          onTap: () => openProfile(context, person.profileId),
          customBorder: const CircleBorder(),
          child: UserAvatar(
            name: person.displayName,
            url: person.avatarUrl,
            radius: 16,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            person.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (trailing != null)
          Text(trailing!, style: TextStyle(color: AppColors.primaryTint, fontSize: 13)),
        ?menu,
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: AppColors.textFaint),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
      ],
    );
  }
}
