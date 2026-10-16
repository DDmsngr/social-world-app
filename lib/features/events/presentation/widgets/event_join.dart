import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../domain/entities/event.dart';
import '../providers/events_providers.dart';

/// Подпись кнопки входа на событие по режиму и состоянию.
String eventJoinLabel(Event e) {
  if (e.joinedByMe) return e.joinMode == EventJoinMode.invite ? 'Вы приглашены' : 'Вы участвуете';
  switch (e.joinMode) {
    case EventJoinMode.free:
      return e.isFull ? 'Мест нет' : 'Участвовать';
    case EventJoinMode.request:
      return switch (e.myRequestStatus) {
        'pending' => 'Запрос отправлен',
        'rejected' => 'Организатор отклонил запрос',
        _ => e.isFull ? 'Мест нет' : 'Попросить принять',
      };
    case EventJoinMode.invite:
      return 'Только по приглашению';
  }
}

/// Можно ли нажать кнопку: решает режим, лимит и ответ организатора.
bool eventJoinEnabled(Event e) {
  if (e.joinedByMe) return e.joinMode != EventJoinMode.invite;
  switch (e.joinMode) {
    case EventJoinMode.free:
      return !e.isFull;
    case EventJoinMode.request:
      return !e.isFull && e.myRequestStatus != 'rejected';
    case EventJoinMode.invite:
      return false;
  }
}

/// «3 из 10» или «3 идёт»: число участников с лимитом, если он есть.
String eventPeopleText(Event e) =>
    e.maxParticipants == null ? '${e.participantCount} идёт' : '${e.participantCount} из ${e.maxParticipants}';

/// Кнопка входа на событие во всех режимах. Свободный вход и выход — как
/// раньше; по запросу — лист «Расскажите о себе»; по приглашению — без кнопки.
class EventJoinButton extends ConsumerWidget {
  const EventJoinButton({super.key, required this.event, this.onChanged});

  final Event event;

  /// После любого изменения участия (список участников надо перечитать).
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = event;
    final pending = e.joinMode == EventJoinMode.request && !e.joinedByMe && e.myRequestStatus == 'pending';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton(
          onPressed: eventJoinEnabled(e) && !pending ? () => _tap(context, ref) : null,
          style: e.joinedByMe || pending
              ? FilledButton.styleFrom(backgroundColor: AppColors.card, foregroundColor: AppColors.primaryTint)
              : null,
          child: Text(eventJoinLabel(e)),
        ),
        if (pending)
          TextButton(
            onPressed: () async {
              try {
                await ref.read(eventsProvider.notifier).withdrawRequest(e);
              } catch (error) {
                if (context.mounted) _toast(context, eventJoinErrorText(error));
              }
            },
            child: const Text('Отозвать запрос'),
          ),
        if (e.joinMode == EventJoinMode.request && e.myRequestStatus == 'rejected' && !e.joinedByMe)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Повторно просить об участии нельзя.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
            ),
          ),
      ],
    );
  }

  Future<void> _tap(BuildContext context, WidgetRef ref) async {
    final e = event;
    if (e.joinMode == EventJoinMode.request && !e.joinedByMe) {
      await showJoinRequestSheet(context, ref, e);
      onChanged?.call();
      return;
    }
    final ok = await ref.read(eventsProvider.notifier).toggleJoin(e);
    onChanged?.call();
    if (!ok && context.mounted) _toast(context, 'Не удалось записаться — нет связи');
  }
}

void _toast(BuildContext context, String text) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

/// Лист «Расскажите о себе»: рассказ обязателен, «зачем хочу прийти» — нет.
Future<void> showJoinRequestSheet(BuildContext context, WidgetRef ref, Event event) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.ink2,
    builder: (sheet) => _JoinRequestSheet(event: event),
  );
}

class _JoinRequestSheet extends ConsumerStatefulWidget {
  const _JoinRequestSheet({required this.event});

  final Event event;

  @override
  ConsumerState<_JoinRequestSheet> createState() => _JoinRequestSheetState();
}

class _JoinRequestSheetState extends ConsumerState<_JoinRequestSheet> {
  final _about = TextEditingController();
  final _message = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _about.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final about = _about.text.trim();
    if (about.length < 5) {
      _toast(context, 'Расскажите о себе хотя бы пару слов');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(eventsProvider.notifier).requestJoin(widget.event, about: about, message: _message.text.trim());
      if (!mounted) return;
      Navigator.of(context).pop();
      _toast(context, 'Запрос отправлен организатору');
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(context, eventJoinErrorText(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 18, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Расскажите о себе', style: AppTypography.serif(22)),
            const SizedBox(height: 6),
            Text(
              'Организатор «${widget.event.title}» сам решает, кого принять. Напишите, кто вы и чем занимаетесь.',
              style: TextStyle(color: AppColors.textDim),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _about,
              maxLength: 400,
              minLines: 3,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'О себе', alignLabelWithHint: true),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _message,
              maxLength: 300,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Почему хотите прийти (необязательно)',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy ? null : _send,
                child: Text(_busy ? 'Отправляем…' : 'Отправить запрос'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Запросы к моей встрече: рассказ человека, «принять» и «отклонить».
Future<void> showEventRequestsSheet(BuildContext context, Event event) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.ink2,
    builder: (sheet) => _RequestsSheet(event: event),
  );
}

class _RequestsSheet extends ConsumerWidget {
  const _RequestsSheet({required this.event});

  final Event event;

  Future<void> _decide(BuildContext context, WidgetRef ref, JoinRequest r, bool approve) async {
    try {
      await ref.read(eventsRepositoryProvider).decideRequest(r.id, approve: approve);
      ref.invalidate(eventRequestsProvider(event.id));
      ref.invalidate(eventParticipantsProvider(event.id));
      await ref.read(eventsProvider.notifier).reload(event.id);
    } catch (error) {
      if (context.mounted) _toast(context, eventJoinErrorText(error));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = ref.watch(eventRequestsProvider(event.id));
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        children: [
          Text('Запросы на участие', style: AppTypography.serif(22)),
          const SizedBox(height: 4),
          Text(event.title, style: TextStyle(color: AppColors.textDim)),
          const SizedBox(height: 12),
          ...requests.when(
            loading: () => [
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            ],
            error: (e, _) => [Text(eventJoinErrorText(e))],
            data: (list) => list.isEmpty
                ? [
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Запросов пока нет.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textDim),
                      ),
                    ),
                  ]
                : [
                    for (final r in list)
                      _RequestTile(request: r, onDecide: (approve) => _decide(context, ref, r, approve)),
                  ],
          ),
        ],
      ),
    );
  }
}

class _RequestTile extends StatelessWidget {
  const _RequestTile({required this.request, required this.onDecide});

  final JoinRequest request;
  final void Function(bool approve) onDecide;

  @override
  Widget build(BuildContext context) {
    final r = request;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.hair),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              UserAvatar(name: r.displayName, url: r.avatarUrl, radius: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(r.displayName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
              ),
              if (!r.isPending)
                Text(
                  r.status == 'approved' ? 'принят' : 'отклонён',
                  style: TextStyle(
                    color: r.status == 'approved' ? AppColors.success : AppColors.textDim,
                    fontSize: 12.5,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(r.about),
          if (r.message != null && r.message!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(r.message!, style: TextStyle(color: AppColors.textDim)),
          ],
          if (r.isPending) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton(onPressed: () => onDecide(true), child: const Text('Принять')),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(onPressed: () => onDecide(false), child: const Text('Отклонить')),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Приглашение друзей: выбор из списка и «Позвать» — они сразу в участниках.
Future<void> showInviteSheet(BuildContext context, Event event) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.ink2,
    builder: (sheet) => _InviteSheet(event: event),
  );
}

class _InviteSheet extends ConsumerStatefulWidget {
  const _InviteSheet({required this.event});

  final Event event;

  @override
  ConsumerState<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends ConsumerState<_InviteSheet> {
  final _picked = <String>{};
  String _query = '';
  bool _busy = false;

  Future<void> _send() async {
    setState(() => _busy = true);
    try {
      final res = await ref.read(eventsRepositoryProvider).invite(widget.event.id, _picked.toList());
      ref.invalidate(eventParticipantsProvider(widget.event.id));
      await ref.read(eventsProvider.notifier).reload(widget.event.id);
      if (!mounted) return;
      Navigator.of(context).pop();
      _toast(
        context,
        res.full > 0
            ? 'Позвали: ${res.added}. Не хватило мест: ${res.full}'
            : 'Позвали: ${res.added}. Они уже в участниках',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(context, eventJoinErrorText(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final candidates = ref.watch(inviteCandidatesProvider((eventId: widget.event.id, query: _query)));
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scroll) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Позвать друзей', style: AppTypography.serif(22)),
                const SizedBox(height: 4),
                Text('Они сразу окажутся в участниках встречи.', style: TextStyle(color: AppColors.textDim)),
                const SizedBox(height: 10),
                TextField(
                  onChanged: (v) => setState(() => _query = v.trim()),
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Найти по имени'),
                ),
              ],
            ),
          ),
          Expanded(
            child: candidates.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text(eventJoinErrorText(e))),
              data: (list) => list.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _query.isEmpty
                              ? 'Звать можно друзей: тех, на кого вы подписаны или кто подписан на вас.'
                              : 'Никого не нашли.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textDim),
                        ),
                      ),
                    )
                  : ListView(
                      controller: scroll,
                      children: [
                        for (final c in list)
                          CheckboxListTile(
                            value: _picked.contains(c.profileId),
                            onChanged: (v) =>
                                setState(() => v == true ? _picked.add(c.profileId) : _picked.remove(c.profileId)),
                            secondary: UserAvatar(name: c.displayName, url: c.avatarUrl, radius: 18),
                            title: Text(c.displayName),
                            subtitle: c.username == null ? null : Text('@${c.username}'),
                          ),
                      ],
                    ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _picked.isEmpty || _busy ? null : _send,
                  child: Text(_picked.isEmpty ? 'Выберите друзей' : 'Позвать (${_picked.length})'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
