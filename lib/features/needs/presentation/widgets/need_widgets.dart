import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/sw_widgets.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../domain/entities/need_request.dart';
import '../providers/needs_providers.dart';

const _months = [
  'янв', 'фев', 'мар', 'апр', 'мая', 'июн',
  'июл', 'авг', 'сен', 'окт', 'ноя', 'дек',
];

/// «до 3 окт» — сколько ещё просьба висит на карте.
String formatNeedExpiry(NeedRequest need) {
  if (need.status == NeedStatus.closed) return NeedStatus.closed.label;
  final expires = need.expiresAt?.toLocal();
  if (expires == null) return NeedStatus.open.label;
  if (need.isExpired) return 'Срок истёк';
  return 'Актуально до ${expires.day} ${_months[expires.month - 1]}';
}

String formatResponses(int n) {
  final mod10 = n % 10;
  final mod100 = n % 100;
  final word = mod10 == 1 && mod100 != 11
      ? 'отклик'
      : mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)
      ? 'отклика'
      : 'откликов';
  return '$n $word';
}

/// Просьба поверх Pulse: текст, автор, где примерно, кнопка «Могу помочь».
Future<void> showNeedSheet(BuildContext context, NeedRequest need) =>
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(AppSpacing.gutter),
        child: SheetCard(child: _NeedSheet(fallback: need)),
      ),
    );

class _NeedSheet extends ConsumerWidget {
  const _NeedSheet({required this.fallback});

  final NeedRequest fallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final need = ref.watch(needProvider(fallback.id)).value ?? fallback;
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel('Мне надо · ${formatNeedExpiry(need)}'),
        const SizedBox(height: 12),
        Text(need.text, style: AppTypography.serif(24)),
        const SizedBox(height: 10),
        InkWell(
          onTap: () {
            Navigator.of(context).pop();
            openProfile(context, need.authorId);
          },
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                UserAvatar(name: need.authorName, url: need.authorAvatarUrl, radius: 11),
                const SizedBox(width: 8),
                Text(
                  need.authorName,
                  style: TextStyle(color: AppColors.primaryTint, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
        Text(
          [
            need.placeTitle ?? 'Точное место не показывается',
            if (need.replyCount > 0) formatResponses(need.replyCount),
          ].join(' · '),
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        NeedRespondButton(need: need),
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
            context.push('${Routes.needDetail}/${need.id}', extra: need);
          },
          child: const Text('Подробнее'),
        ),
      ],
    );
  }
}

/// «Могу помочь» / «Вы откликнулись». Своя просьба — без кнопки.
class NeedRespondButton extends ConsumerStatefulWidget {
  const NeedRespondButton({super.key, required this.need});

  final NeedRequest need;

  @override
  ConsumerState<NeedRespondButton> createState() => _NeedRespondButtonState();
}

class _NeedRespondButtonState extends ConsumerState<NeedRespondButton> {
  var _busy = false;

  Future<void> _run(Future<String?> Function() action, String success) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final error = await action();
    if (mounted) setState(() => _busy = false);
    messenger.showSnackBar(SnackBar(content: Text(error ?? success)));
  }

  Future<void> _respond() async {
    final text = await showNeedResponseSheet(context);
    if (text == null || !mounted) return;
    await _run(
      () => ref.read(needActionsProvider).respond(widget.need.id, text: text),
      'Автор увидит ваш отклик',
    );
  }

  @override
  Widget build(BuildContext context) {
    final need = widget.need;
    final me = ref.watch(currentUserProvider)?.id;
    if (me == need.authorId) {
      return Text(
        need.replyCount == 0
            ? 'Это ваша просьба. Откликов пока нет.'
            : 'Это ваша просьба · ${formatResponses(need.replyCount)}',
        style: Theme.of(context).textTheme.bodyMedium,
      );
    }
    if (!need.isVisible) {
      return FilledButton(onPressed: null, child: Text(formatNeedExpiry(need)));
    }
    if (need.respondedByMe) {
      return OutlinedButton(
        onPressed: _busy
            ? null
            : () => _run(
                () => ref.read(needActionsProvider).withdrawResponse(need.id),
                'Отклик отозван',
              ),
        child: const Text('Вы откликнулись · отозвать'),
      );
    }
    return FilledButton.icon(
      onPressed: _busy ? null : _respond,
      icon: const Icon(Icons.volunteer_activism_outlined),
      label: const Text('Могу помочь'),
    );
  }
}

/// Короткий отклик. Он публичный, как комментарий: личной переписки в
/// продукте пока нет. Возвращает текст (может быть пустым) или `null`.
Future<String?> showNeedResponseSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.gutter,
        AppSpacing.gutter,
        AppSpacing.gutter + MediaQuery.viewInsetsOf(sheetContext).bottom,
      ),
      child: const SheetCard(child: _NeedResponseForm()),
    ),
  );
}

class _NeedResponseForm extends StatefulWidget {
  const _NeedResponseForm();

  @override
  State<_NeedResponseForm> createState() => _NeedResponseFormState();
}

class _NeedResponseFormState extends State<_NeedResponseForm> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Могу помочь'),
        const SizedBox(height: 12),
        Text(
          'Отклик увидят все, кто открывает эту просьбу. Не пишите телефон '
          'и адрес — автор откроет ваш профиль.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _controller,
          autofocus: true,
          maxLength: 300,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'Например: «Могу завтра вечером»',
          ),
        ),
        const SizedBox(height: 10),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Откликнуться'),
        ),
      ],
    );
  }
}