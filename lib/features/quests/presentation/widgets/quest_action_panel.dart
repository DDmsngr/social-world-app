import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../domain/entities/quest.dart';
import '../providers/quests_providers.dart';
import 'arrival_code_sheet.dart';
import 'quest_format.dart';
import 'quest_qr_sheet.dart';

/// Кнопки квеста по состоянию участия — ровно как в ТЗ (п. 22, 23):
/// до заявки — «Подать заявку»; после одобрения главная кнопка меняется на
/// «Завершить квест», рядом «Построить маршрут» и маленькое «Отказаться».
/// У организатора — QR и завершение квеста целиком.
class QuestActionPanel extends ConsumerStatefulWidget {
  const QuestActionPanel({super.key, required this.quest, this.compact = false});

  final Quest quest;

  /// В листе на карте — без второстепенных кнопок.
  final bool compact;

  @override
  ConsumerState<QuestActionPanel> createState() => _QuestActionPanelState();
}

class _QuestActionPanelState extends ConsumerState<QuestActionPanel> {
  var _busy = false;

  Quest get quest => widget.quest;

  void _toast(String text, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), action: action),
    );
  }

  Future<void> _run(
    Future<String?> Function(QuestActions actions) action, {
    String? success,
    SnackBarAction? successAction,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final error = await action(ref.read(questActionsProvider));
    if (mounted) setState(() => _busy = false);
    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text(error)));
    } else if (success != null) {
      messenger.showSnackBar(SnackBar(content: Text(success), action: successAction));
    }
  }

  Future<bool> _confirm(String title, String text, String yes) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Нет'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(yes),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _join() => _run(
    (a) => a.requestJoin(quest.id),
    success: quest.needsApproval
        ? 'Заявка отправлена организатору'
        : 'Вы участвуете',
  );

  Future<void> _withdraw() async {
    final requested = quest.myStatus == QuestParticipationStatus.requested;
    if (!await _confirm(
      requested ? 'Отозвать заявку?' : 'Отказаться от квеста?',
      requested
          ? 'Организатор больше не увидит вашу заявку.'
          : 'Место освободится для других, вы выйдете из квест-чата.',
      requested ? 'Отозвать' : 'Отказаться',
    )) {
      return;
    }
    await _run((a) => a.withdraw(quest.id));
  }

  Future<void> _complete() async {
    final router = GoRouter.of(context);
    await _run(
      (a) => a.complete(quest.id),
      success: 'Участие завершено',
      // Сразу после квеста — лучший момент для Quest Moment (п. 37).
      successAction: SnackBarAction(
        label: 'Добавить момент',
        onPressed: () => router.push(
          '${Routes.questDetail}/${quest.id}/moment',
          extra: quest,
        ),
      ),
    );
  }

  Future<void> _arrive() async {
    final code = await showArrivalCodeSheet(context);
    if (code == null || !mounted) return;
    await _run(
      (a) => a.confirmArrival(quest.id, code),
      success: 'Вы на месте. Хорошего квеста!',
    );
  }

  Future<void> _finishQuest() async {
    if (!await _confirm(
      'Завершить квест?',
      'Новые заявки перестанут приниматься, квест-чат закроется. Если у '
          'квеста есть моменты, он ещё сутки будет виден на карте.',
      'Завершить',
    )) {
      return;
    }
    await _run((a) => a.finish(quest.id), success: 'Квест завершён');
  }

  Future<void> _route() async {
    if (!await openQuestRoute(quest) && mounted) {
      _toast('Не удалось открыть карты');
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentUserProvider)?.id;
    final isAuthor = me != null && me == quest.authorId;
    final status = quest.myStatus;

    final children = <Widget>[];
    void gap() => children.add(const SizedBox(height: 8));

    final routeButton = quest.hasLocation && quest.isActive
        ? OutlinedButton.icon(
            onPressed: _route,
            icon: const Icon(Icons.directions_outlined),
            label: const Text('Построить маршрут'),
          )
        : null;

    final canAddMoment = !widget.compact &&
        quest.status != QuestStatus.cancelled &&
        (isAuthor ||
            status == QuestParticipationStatus.approved ||
            status == QuestParticipationStatus.arrived ||
            status == QuestParticipationStatus.completed);

    if (isAuthor) {
      children.add(_Note(icon: Icons.verified_outlined, text: 'Вы организатор'));
      if (quest.isActive) {
        gap();
        children.add(
          FilledButton.icon(
            onPressed: () => showQuestQrSheet(context, quest),
            icon: const Icon(Icons.qr_code_2),
            label: const Text('Показать QR прибытия'),
          ),
        );
        if (!widget.compact) {
          gap();
          children.add(
            OutlinedButton(
              onPressed: _busy ? null : _finishQuest,
              child: const Text('Завершить квест'),
            ),
          );
        }
      }
    } else if (!quest.isActive) {
      children.add(
        _Note(
          icon: Icons.flag_circle_outlined,
          text: switch (status) {
            QuestParticipationStatus.completed => 'Вы прошли этот квест',
            _ when quest.status == QuestStatus.cancelled => 'Квест отменён',
            _ => 'Квест завершён',
          },
        ),
      );
    } else {
      switch (status) {
        case null ||
            QuestParticipationStatus.withdrawn ||
            QuestParticipationStatus.completed:
          if (status == QuestParticipationStatus.completed) {
            children.add(
              _Note(icon: Icons.check_circle_outline, text: 'Вы завершили участие'),
            );
            gap();
          }
          children.add(
            FilledButton(
              onPressed: _busy || !quest.acceptsRequests ? null : _join,
              child: Text(
                quest.isFull
                    ? 'Мест нет'
                    : status == QuestParticipationStatus.completed
                    ? 'Участвовать снова'
                    : quest.needsApproval
                    ? 'Подать заявку'
                    : 'Участвовать',
              ),
            ),
          );
        case QuestParticipationStatus.requested:
          children.add(
            const FilledButton(onPressed: null, child: Text('Заявка отправлена')),
          );
          children.add(
            TextButton(
              onPressed: _busy ? null : _withdraw,
              child: const Text('Отозвать заявку'),
            ),
          );
        case QuestParticipationStatus.approved || QuestParticipationStatus.arrived:
          if (status == QuestParticipationStatus.arrived) {
            children.add(_Note(icon: Icons.place, text: 'Вы на месте'));
            gap();
          }
          children.add(
            FilledButton(
              onPressed: _busy ? null : _complete,
              child: const Text('Завершить квест'),
            ),
          );
          if (status == QuestParticipationStatus.approved) {
            gap();
            children.add(
              OutlinedButton.icon(
                onPressed: _busy ? null : _arrive,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Я на месте — ввести код'),
              ),
            );
          }
        case QuestParticipationStatus.rejected:
          children.add(
            _Note(icon: Icons.block, text: 'Организатор не принял заявку'),
          );
        case QuestParticipationStatus.removed:
          children.add(_Note(icon: Icons.block, text: 'Вас исключили из квеста'));
      }
    }

    if (routeButton != null) {
      gap();
      children.add(routeButton);
    }

    if (canAddMoment) {
      gap();
      children.add(
        OutlinedButton.icon(
          onPressed: () => context.push(
            '${Routes.questDetail}/${quest.id}/moment',
            extra: quest,
          ),
          icon: const Icon(Icons.add_a_photo_outlined),
          label: const Text('Добавить момент'),
        ),
      );
    }

    // «Отказаться» — маленькой ссылкой под кнопками, как в ТЗ (п. 23).
    if (!isAuthor &&
        quest.isActive &&
        (status == QuestParticipationStatus.approved ||
            status == QuestParticipationStatus.arrived)) {
      children.add(
        Center(
          child: TextButton(
            onPressed: _busy ? null : _withdraw,
            child: Text('Отказаться', style: TextStyle(color: AppColors.textDim)),
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.hair),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.primaryTint),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
