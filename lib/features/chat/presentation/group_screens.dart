import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/debug/app_log.dart';
import '../../../core/errors/friendly_error.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/state_message.dart';
import '../../../core/widgets/sw_widgets.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../profile/domain/profile_models.dart';
import '../../profile/presentation/providers/profile_providers.dart';
import 'conversations_screen.dart';
import 'providers/chat_providers.dart';

void _showError(BuildContext context, Object error, String fallback) {
  AppLog.add('$fallback: $error');
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(friendlyError(error, fallback: fallback))),
  );
}

/// Новая группа: название и участники.
class CreateGroupScreen extends ConsumerStatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  ConsumerState<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends ConsumerState<CreateGroupScreen> {
  final _title = TextEditingController();
  final _selected = <String, ProfileHit>{};
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() => _saving = true);
    try {
      final id = await ref
          .read(chatRepositoryProvider)
          .createGroup(title: _title.text, memberIds: _selected.keys.toList());
      ref.invalidate(conversationsProvider);
      if (mounted) {
        context.pushReplacement('${Routes.chats}/$id', extra: _title.text.trim());
      }
    } catch (error) {
      if (mounted) _showError(context, error, 'Не удалось создать группу');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = _title.text.trim().isNotEmpty && !_saving;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Новая группа'),
        actions: [
          TextButton(
            onPressed: ready ? _create : null,
            child: const Text('Создать'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.gutter,
              12,
              AppSpacing.gutter,
              4,
            ),
            child: TextField(
              controller: _title,
              maxLength: 80,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(hintText: 'Название группы'),
            ),
          ),
          Expanded(
            child: PeoplePicker(
              selected: _selected,
              onToggle: (hit) => setState(() {
                _selected.containsKey(hit.id)
                    ? _selected.remove(hit.id)
                    : _selected[hit.id] = hit;
              }),
            ),
          ),
        ],
      ),
    );
  }
}

/// Добавление участников в существующую группу. Возвращает выбранные id.
class AddMembersScreen extends StatefulWidget {
  const AddMembersScreen({super.key, required this.existing});

  final Set<String> existing;

  @override
  State<AddMembersScreen> createState() => _AddMembersScreenState();
}

class _AddMembersScreenState extends State<AddMembersScreen> {
  final _selected = <String, ProfileHit>{};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Добавить участников'),
        actions: [
          TextButton(
            onPressed: _selected.isEmpty
                ? null
                : () => Navigator.of(context).pop(_selected.keys.toList()),
            child: const Text('Готово'),
          ),
        ],
      ),
      body: PeoplePicker(
        selected: _selected,
        exclude: widget.existing,
        onToggle: (hit) => setState(() {
          _selected.containsKey(hit.id)
              ? _selected.remove(hit.id)
              : _selected[hit.id] = hit;
        }),
      ),
    );
  }
}

/// Выбор людей: без запроса — мои подписки, с запросом от двух букв — поиск.
class PeoplePicker extends ConsumerStatefulWidget {
  const PeoplePicker({
    super.key,
    required this.selected,
    required this.onToggle,
    this.exclude = const {},
  });

  final Map<String, ProfileHit> selected;
  final ValueChanged<ProfileHit> onToggle;
  final Set<String> exclude;

  @override
  ConsumerState<PeoplePicker> createState() => _PeoplePickerState();
}

class _PeoplePickerState extends ConsumerState<PeoplePicker> {
  Timer? _debounce;
  String _query = '';
  Future<List<ProfileHit>>? _results;

  @override
  void initState() {
    super.initState();
    _results = _load('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<List<ProfileHit>> _load(String query) {
    final repository = ref.read(profileRepositoryProvider);
    if (query.trim().length >= 2) return repository.searchProfiles(query);
    final me = ref.read(currentUserProvider)?.id;
    if (me == null) return Future.value(const []);
    return repository.loadFollowList(me, FollowList.following);
  }

  void _onQuery(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() {
        _query = value;
        _results = _load(value);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentUserProvider)?.id;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            8,
            AppSpacing.gutter,
            8,
          ),
          child: TextField(
            onChanged: _onQuery,
            decoration: const InputDecoration(
              hintText: 'Найти человека',
              prefixIcon: Icon(Icons.search),
            ),
          ),
        ),
        if (widget.selected.isNotEmpty)
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
              children: [
                for (final hit in widget.selected.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: InputChip(
                      label: Text(hit.displayName),
                      onDeleted: () => widget.onToggle(hit),
                    ),
                  ),
              ],
            ),
          ),
        Expanded(
          child: FutureBuilder<List<ProfileHit>>(
            future: _results,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const LoadingView();
              }
              if (snapshot.hasError) {
                return StateMessage.error(
                  onAction: () => setState(() => _results = _load(_query)),
                );
              }
              final items = [
                for (final hit in snapshot.data ?? const <ProfileHit>[])
                  if (hit.id != me && !widget.exclude.contains(hit.id)) hit,
              ];
              if (items.isEmpty) {
                return StateMessage(
                  title: _query.trim().length >= 2
                      ? 'Никого не нашли'
                      : 'Найдите людей через поиск',
                  text: _query.trim().length >= 2
                      ? null
                      : 'Здесь показываются ваши подписки.',
                  icon: Icons.person_search_outlined,
                );
              }
              return ListView.builder(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.gutter,
                  0,
                  AppSpacing.gutter,
                  MediaQuery.paddingOf(context).bottom,
                ),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final hit = items[index];
                  return CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: widget.selected.containsKey(hit.id),
                    onChanged: (_) => widget.onToggle(hit),
                    secondary: UserAvatar(
                      name: hit.displayName,
                      url: hit.avatarUrl,
                    ),
                    title: Text(hit.displayName),
                    subtitle: hit.username == null ? null : Text('@${hit.username}'),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Карточка группы: участники, добавление, переименование, выход.
class GroupInfoScreen extends ConsumerWidget {
  const GroupInfoScreen({super.key, required this.conversationId});

  final String conversationId;

  Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) async {
    final controller = TextEditingController(text: current);
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Название группы'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (title == null || title.trim().isEmpty) return;
    try {
      await ref.read(chatRepositoryProvider).renameGroup(conversationId, title);
      ref
        ..invalidate(conversationProvider(conversationId))
        ..invalidate(conversationsProvider);
    } catch (error) {
      if (context.mounted) _showError(context, error, 'Не удалось переименовать');
    }
  }

  Future<void> _add(
    BuildContext context,
    WidgetRef ref,
    Set<String> existing,
  ) async {
    final ids = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (_) => AddMembersScreen(existing: existing),
      ),
    );
    if (ids == null || ids.isEmpty) return;
    try {
      await ref.read(chatRepositoryProvider).addMembers(conversationId, ids);
      ref
        ..invalidate(chatMembersProvider(conversationId))
        ..invalidate(conversationProvider(conversationId));
    } catch (error) {
      if (context.mounted) _showError(context, error, 'Не удалось добавить');
    }
  }

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    String memberId, {
    required bool self,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(self ? 'Выйти из группы?' : 'Исключить из группы?'),
        content: self
            ? const Text('Переписка группы пропадёт из вашего списка чатов.')
            : null,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(self ? 'Выйти' : 'Исключить'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(chatRepositoryProvider)
          .removeMember(conversationId, memberId);
      ref.invalidate(conversationsProvider);
      if (self) {
        if (context.mounted) context.go(Routes.chats);
      } else {
        ref
          ..invalidate(chatMembersProvider(conversationId))
          ..invalidate(conversationProvider(conversationId));
      }
    } catch (error) {
      if (context.mounted) _showError(context, error, 'Не удалось выполнить');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversation = ref.watch(conversationProvider(conversationId));
    final members = ref.watch(chatMembersProvider(conversationId));
    final me = ref.watch(currentUserProvider)?.id;
    final info = conversation.value;
    final manageable = info?.isGroup ?? false;
    final owner = info?.isOwner ?? false;

    return Scaffold(
      appBar: AppBar(title: Text(manageable ? 'О группе' : 'Участники')),
      body: members.when(
        loading: () => const LoadingView(),
        error: (_, _) => StateMessage.error(
          onAction: () => ref.invalidate(chatMembersProvider(conversationId)),
        ),
        data: (items) => ListView(
          padding: AppSpacing.page(context, top: 12),
          children: [
            if (info != null) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      info.displayName,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  if (manageable && owner)
                    IconButton(
                      onPressed: () =>
                          _rename(context, ref, info.displayName),
                      tooltip: 'Переименовать',
                      icon: const Icon(Icons.edit_outlined),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                membersLabel(items.length),
                style: TextStyle(color: AppColors.textDim),
              ),
              const SizedBox(height: 16),
            ],
            if (manageable) ...[
              GlassCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                onTap: () =>
                    _add(context, ref, {for (final m in items) m.id}),
                child: Row(
                  children: [
                    Icon(Icons.person_add_alt, color: AppColors.primaryTint),
                    const SizedBox(width: 14),
                    const Expanded(child: Text('Добавить участников')),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            for (final member in items)
              ListTile(
                contentPadding: EdgeInsets.zero,
                onTap: () => openProfile(context, member.id),
                leading: UserAvatar(name: member.name, url: member.avatarUrl),
                title: Text(member.id == me ? '${member.name} (вы)' : member.name),
                subtitle: member.isOwner ? const Text('Создатель') : null,
                trailing: manageable && owner && member.id != me
                    ? IconButton(
                        onPressed: () =>
                            _remove(context, ref, member.id, self: false),
                        tooltip: 'Исключить',
                        icon: const Icon(Icons.remove_circle_outline),
                      )
                    : null,
              ),
            if (manageable && me != null) ...[
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: () => _remove(context, ref, me, self: true),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.danger,
                ),
                icon: const Icon(Icons.logout),
                label: const Text('Выйти из группы'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
