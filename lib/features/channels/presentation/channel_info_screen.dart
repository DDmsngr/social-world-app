import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/debug/app_log.dart';
import '../../../core/errors/friendly_error.dart';
import '../../../core/links/deep_links.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/state_message.dart';
import '../../../core/widgets/sw_widgets.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../chat/presentation/providers/chat_providers.dart';
import '../data/channels_repository.dart';
import 'channel_screen.dart';
import 'providers/channel_providers.dart';

/// О канале: описание, ссылка, заявки на вступление, настройки владельца,
/// отписка.
class ChannelInfoScreen extends ConsumerWidget {
  const ChannelInfoScreen({super.key, required this.channelId});

  final String channelId;

  void _snack(BuildContext context, String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _share(BuildContext context, WidgetRef ref, ChannelInfo info) async {
    final Uri link;
    if (info.isPublic) {
      link = DeepLinks.shareUri(LinkTarget.channel, info.id);
    } else {
      final token = info.inviteToken;
      if (token == null) return;
      link = DeepLinks.channelInviteUri(info.id, token);
    }
    final text = info.isPublic
        ? 'Канал «${info.title}» (@${info.handle}) в ChaWo: $link'
        : 'Приглашение в канал «${info.title}» в ChaWo: $link';
    await SharePlus.instance.share(ShareParams(text: text));
  }

  Future<void> _regenerate(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(channelsRepositoryProvider).regenerateInvite(channelId);
      ref.invalidate(channelInfoProvider(channelId));
      if (context.mounted) _snack(context, 'Старая ссылка больше не работает');
    } catch (error) {
      AppLog.add('Новая ссылка канала: $error');
    }
  }

  Future<void> _leave(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(channelsRepositoryProvider).leave(channelId);
      ref.invalidate(conversationsProvider);
      ref.invalidate(channelInfoProvider(channelId));
      if (context.mounted) context.go(Routes.chats);
    } catch (error) {
      if (context.mounted) {
        _snack(context, friendlyError(error, fallback: 'Не удалось отписаться'));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final infoAsync = ref.watch(channelInfoProvider(channelId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('О канале'),
        leading: IconButton(
          onPressed: () => context.canPop() ? context.pop() : context.go(Routes.channel(channelId)),
          tooltip: 'Назад',
          icon: const Icon(Icons.arrow_back),
        ),
        actions: [
          if (infoAsync.value?.isOwner ?? false)
            IconButton(
              onPressed: () => _edit(context, ref, infoAsync.value!),
              tooltip: 'Настройки канала',
              icon: const Icon(Icons.edit_outlined),
            ),
        ],
      ),
      body: infoAsync.when(
        loading: () => const LoadingView(),
        error: (_, _) => StateMessage.error(
          onAction: () => ref.invalidate(channelInfoProvider(channelId)),
        ),
        data: (info) {
          if (info == null) {
            return const StateMessage(title: 'Канал не найден', icon: Icons.campaign_outlined);
          }
          return ListView(
            padding: AppSpacing.page(context, top: 16),
            children: [
              Center(
                child: CircleAvatar(
                  radius: 40,
                  backgroundColor: AppColors.ink,
                  child: Icon(Icons.campaign_outlined, color: AppColors.primaryTint, size: 34),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(info.title, style: Theme.of(context).textTheme.headlineSmall),
              ),
              const SizedBox(height: 4),
              Center(
                child: Text(
                  [
                    info.isPublic ? '@${info.handle}' : 'закрытый канал',
                    info.topic.label,
                    if (info.subscriberCount != null) subscribersLabel(info.subscriberCount!),
                  ].join(' · '),
                  style: TextStyle(color: AppColors.textDim),
                ),
              ),
              if (info.description != null) ...[
                const SizedBox(height: 16),
                Text(info.description!),
              ],
              const SizedBox(height: 20),
              if (info.isPublic || info.inviteToken != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.share_outlined),
                  title: Text(info.isPublic ? 'Поделиться каналом' : 'Пригласить по ссылке'),
                  onTap: () => _share(context, ref, info),
                ),
              if (!info.isPublic && info.isAdmin)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.link_off),
                  title: const Text('Сбросить ссылку-приглашение'),
                  subtitle: const Text('Старая ссылка перестанет работать'),
                  onTap: () => _regenerate(context, ref),
                ),
              if (info.isPublic)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.alternate_email),
                  title: const Text('Скопировать адрес'),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: '@${info.handle}'));
                    _snack(context, 'Адрес скопирован');
                  },
                ),
              if (info.isAdmin && info.pendingRequests > 0) ...[
                const SizedBox(height: 16),
                SectionLabel('Заявки · ${info.pendingRequests}'),
                _Requests(channelId: channelId),
              ],
              if (info.isMember && !info.isOwner) ...[
                const SizedBox(height: 24),
                OutlinedButton(
                  onPressed: () => _leave(context, ref),
                  child: const Text('Отписаться'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, ChannelInfo info) async {
    final title = TextEditingController(text: info.title);
    final description = TextEditingController(text: info.description ?? '');
    final handle = TextEditingController(text: info.handle ?? '');
    var isPublic = info.isPublic;
    var showSubscribers = info.showSubscribers;
    var topic = info.topic;

    final save = await showModalBottomSheet<bool>(
      context: context, useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.ink2,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
            20, 12, 20, 20 + MediaQuery.viewInsetsOf(sheet).bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Настройки канала', style: Theme.of(sheet).textTheme.titleLarge),
                const SizedBox(height: 12),
                TextField(
                  controller: title,
                  maxLength: 80,
                  decoration: const InputDecoration(labelText: 'Название'),
                ),
                TextField(
                  controller: description,
                  maxLength: 500,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(labelText: 'Описание'),
                ),
                const SizedBox(height: 8),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('Публичный')),
                    ButtonSegment(value: false, label: Text('Закрытый')),
                  ],
                  selected: {isPublic},
                  onSelectionChanged: (v) => setSheet(() => isPublic = v.first),
                ),
                if (isPublic) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: handle,
                    maxLength: 32,
                    autocorrect: false,
                    decoration: const InputDecoration(labelText: 'Адрес', prefixText: '@'),
                  ),
                ],
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: showSubscribers,
                  onChanged: (v) => setSheet(() => showSubscribers = v),
                  title: const Text('Показывать число подписчиков'),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final t in ChannelTopic.values)
                      ChoiceChip(
                        label: Text(t.label),
                        selected: topic == t,
                        onSelected: (_) => setSheet(() => topic = t),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.pop(sheet, true),
                  child: const Text('Сохранить'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (save == true) {
      try {
        await ref.read(channelsRepositoryProvider).update(
          info,
          title: title.text.trim(),
          description: description.text.trim(),
          isPublic: isPublic,
          handle: isPublic ? handle.text.trim().toLowerCase() : null,
          topic: topic,
          showSubscribers: showSubscribers,
        );
        ref.invalidate(channelInfoProvider(channelId));
        ref.invalidate(conversationsProvider);
      } catch (error) {
        if (context.mounted) {
          _snack(context, friendlyError(error, fallback: 'Не удалось сохранить'));
        }
      }
    }
    title.dispose();
    description.dispose();
    handle.dispose();
  }
}

class _Requests extends ConsumerStatefulWidget {
  const _Requests({required this.channelId});

  final String channelId;

  @override
  ConsumerState<_Requests> createState() => _RequestsState();
}

class _RequestsState extends ConsumerState<_Requests> {
  List<JoinRequest>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await ref.read(channelsRepositoryProvider).requests(widget.channelId);
      if (mounted) setState(() => _items = items);
    } catch (error) {
      AppLog.add('Заявки канала: $error');
    }
  }

  Future<void> _decide(JoinRequest request, bool approve) async {
    await ref
        .read(channelsRepositoryProvider)
        .decide(widget.channelId, request.profileId, approve: approve);
    ref.invalidate(channelInfoProvider(widget.channelId));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    if (items == null) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Column(
      children: [
        for (final r in items)
          ListTile(
            contentPadding: EdgeInsets.zero,
            onTap: () => openProfile(context, r.profileId),
            leading: UserAvatar(name: r.name, url: r.avatarUrl),
            title: Text(r.name),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: () => _decide(r, false),
                  tooltip: 'Отклонить',
                  icon: const Icon(Icons.close),
                ),
                IconButton(
                  onPressed: () => _decide(r, true),
                  tooltip: 'Принять',
                  icon: Icon(Icons.check, color: AppColors.success),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
