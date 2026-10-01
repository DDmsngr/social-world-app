import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/state_message.dart';
import '../../../core/widgets/sw_widgets.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../domain/entities/chat_message.dart';
import '../domain/entities/conversation.dart';
import 'providers/chat_notify_providers.dart';
import 'providers/chat_providers.dart';
import 'widgets/chat_notify_sheet.dart';

enum _Tab { direct, groups, channels }

/// Чаты разложены по вкладкам «Личные / Группы / Каналы» — как в Telegram,
/// но без общей «Все»: переписка с человеком не тонет среди постов каналов.
class ConversationsScreen extends ConsumerStatefulWidget {
  const ConversationsScreen({super.key});

  @override
  ConsumerState<ConversationsScreen> createState() =>
      _ConversationsScreenState();
}

class _ConversationsScreenState extends ConsumerState<ConversationsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this)
    ..addListener(() {
      if (!_tabs.indexIsChanging) setState(() {});
    });

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  static _Tab _tabOf(Conversation c) => switch (c.kind) {
    ConversationKind.direct => _Tab.direct,
    ConversationKind.channel => _Tab.channels,
    _ => _Tab.groups,
  };

  @override
  Widget build(BuildContext context) {
    final conversations = ref.watch(conversationsProvider);
    final encryptionEnabled = ref
        .watch(chatRepositoryProvider)
        .endToEndEncryptionEnabled;
    final all = conversations.value ?? const <Conversation>[];

    // Непрочитанные по вкладке: заглушённые чаты не считаем, они не должны
    // звать внимание и через бейдж.
    int unread(_Tab tab) => all
        .where((c) => _tabOf(c) == tab && c.unreadCount > 0 && !chatNotifyOf(ref, c.id).isMuted)
        .length;

    Widget tabLabel(String text, _Tab tab) {
      final n = unread(tab);
      return Tab(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text),
            if (n > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.champagne,
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                ),
                child: Text(
                  '$n',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.ink),
                ),
              ),
            ],
          ],
        ),
      );
    }

    final current = _Tab.values[_tabs.index];
    final fab = switch (current) {
      _Tab.direct => null,
      _Tab.groups => FloatingActionButton.extended(
        onPressed: () => context.push('${Routes.chats}/new-group'),
        icon: const Icon(Icons.group_add_outlined),
        label: const Text('Группа'),
      ),
      _Tab.channels => FloatingActionButton.extended(
        onPressed: () => context.push(Routes.newChannel),
        icon: const Icon(Icons.campaign_outlined),
        label: const Text('Канал'),
      ),
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Чаты'),
        actions: [
          IconButton(
            onPressed: () => context.push(Routes.channels),
            tooltip: 'Найти каналы',
            icon: const Icon(Icons.travel_explore),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            tabLabel('Личные', _Tab.direct),
            tabLabel('Группы', _Tab.groups),
            tabLabel('Каналы', _Tab.channels),
          ],
        ),
      ),
      floatingActionButton: fab,
      body: conversations.when(
        loading: () => const LoadingView(),
        error: (_, _) => StateMessage.error(
          title: 'Не удалось загрузить чаты',
          onAction: () => ref.invalidate(conversationsProvider),
        ),
        data: (items) => TabBarView(
          controller: _tabs,
          children: [
            for (final tab in _Tab.values)
              RefreshIndicator(
                onRefresh: () => ref.refresh(conversationsProvider.future),
                child: _list(
                  context,
                  [for (final c in items) if (_tabOf(c) == tab) c],
                  tab,
                  showEncryptionNotice: tab == _Tab.direct && !encryptionEnabled,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _list(
    BuildContext context,
    List<Conversation> items,
    _Tab tab, {
    required bool showEncryptionNotice,
  }) {
    final myId = ref.watch(currentUserProvider)?.id;
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 12, AppSpacing.gutter, 96),
      children: [
        if (showEncryptionNotice) ...[
          const _EncryptionNotice(),
          const SizedBox(height: 14),
        ],
        if (tab == _Tab.channels) ...[
          GlassCard(
            padding: const EdgeInsets.all(14),
            onTap: () => context.push(Routes.channels),
            child: Row(
              children: [
                Icon(Icons.travel_explore, color: AppColors.primaryTint),
                const SizedBox(width: 14),
                const Expanded(child: Text('Найти каналы: новости, наука, еда, мемы…')),
                Icon(Icons.chevron_right, color: AppColors.textFaint),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 60),
            child: StateMessage(
              title: switch (tab) {
                _Tab.direct => 'Личных переписок пока нет',
                _Tab.groups => 'Групп пока нет',
                _Tab.channels => 'Вы ни на что не подписаны',
              },
              text: switch (tab) {
                _Tab.direct => 'Откройте профиль человека и нажмите «Написать».',
                _Tab.groups => 'Создайте группу кнопкой внизу.',
                _Tab.channels => 'Загляните в каталог — подписка в одно касание.',
              },
              icon: switch (tab) {
                _Tab.direct => Icons.forum_outlined,
                _Tab.groups => Icons.group_outlined,
                _Tab.channels => Icons.campaign_outlined,
              },
            ),
          ),
        for (final conversation in items) ...[
          _ConversationTile(
            conversation: conversation,
            myId: myId,
            notify: chatNotifyOf(ref, conversation.id),
            onLongPress: () => showChatNotifySheet(
              context,
              conversation.id,
              conversation.displayName,
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.conversation,
    required this.myId,
    required this.notify,
    required this.onLongPress,
  });

  final Conversation conversation;
  final String? myId;
  final ChatNotify notify;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final last = conversation.lastMessage;
    final preview = last == null
        ? (conversation.isChannel ? 'Постов пока нет' : 'Нет сообщений')
        : conversation.isDirect || conversation.isChannel || last.senderName == null
        ? last.preview
        : '${last.senderName}: ${last.preview}';

    return GlassCard(
      padding: const EdgeInsets.all(14),
      onLongPress: onLongPress,
      onTap: () => conversation.isChannel
          ? context.push(Routes.channel(conversation.id))
          : context.push(
              '${Routes.chats}/${conversation.id}',
              extra: conversation.displayName,
            ),
      child: Row(
        children: [
          if (conversation.isDirect)
            UserAvatar(
              name: conversation.displayName,
              url: conversation.peerAvatarUrl,
              radius: 22,
            )
          else
            CircleAvatar(
              radius: 22,
              backgroundColor: AppColors.ink,
              child: Icon(
                switch (conversation.kind) {
                  ConversationKind.quest => Icons.flag_outlined,
                  ConversationKind.channel => Icons.campaign_outlined,
                  _ => Icons.group_outlined,
                },
                color: AppColors.champagne,
                size: 20,
              ),
            ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  conversation.displayName,
                  style: Theme.of(context).textTheme.titleLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    // Своё последнее сообщение — с галочками, как в переписке.
                    if (last != null && last.senderId == myId) ...[
                      Icon(
                        last.status == MessageStatus.read
                            ? Icons.done_all
                            : Icons.done,
                        size: 15,
                        color: last.status == MessageStatus.read
                            ? AppColors.champagne
                            : AppColors.textFaint,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Expanded(
                      child: Text(
                        preview,
                        style: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.copyWith(fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (notify.isCustom) ...[
            const SizedBox(width: 8),
            Icon(
              notify.isMuted
                  ? Icons.notifications_off_outlined
                  : notify.mode == NotifyMode.vibrate
                  ? Icons.vibration
                  : Icons.notifications_none,
              size: 16,
              color: AppColors.textFaint,
            ),
          ],
          if (conversation.unreadCount > 0) ...[
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                // У заглушённого чата счётчик серый: он не должен кричать.
                color: notify.isMuted ? AppColors.hairStrong : AppColors.champagne,
                borderRadius: BorderRadius.circular(AppRadius.chip),
              ),
              child: Text(
                '${conversation.unreadCount}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// В режиме заглушек шифрования нет, и об этом сказано прямо. Мессенджер,
/// который выглядит защищённым, но не защищён, опаснее честной пометки.
class _EncryptionNotice extends StatelessWidget {
  const _EncryptionNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.hairStrong),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_open, size: 17, color: AppColors.textFaint),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Сквозное шифрование ещё не включено. Не обсуждайте здесь ничего '
              'важного.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

/// Подзаголовок для шапки: сколько человек в группе.
String membersLabel(int count) {
  final mod10 = count % 10;
  final mod100 = count % 100;
  final word = mod10 == 1 && mod100 != 11
      ? 'участник'
      : mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)
      ? 'участника'
      : 'участников';
  return '$count $word';
}
