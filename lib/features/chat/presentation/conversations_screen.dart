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
import '../../channels/presentation/widgets/channel_avatar.dart';
import '../domain/entities/chat_message.dart';
import '../domain/entities/conversation.dart';
import 'providers/chat_extras_providers.dart';
import 'providers/chat_notify_providers.dart';
import 'providers/chat_providers.dart';
import 'providers/chat_settings_providers.dart';
import 'providers/chat_typing_providers.dart';
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
    final settings =
        ref.watch(chatSettingsProvider).asData?.value ??
        const <String, ChatSettings>{};
    ChatSettings settingsOf(Conversation c) =>
        settings[c.id] ?? ChatSettings.none;
    final everything = conversations.value ?? const <Conversation>[];
    // Архивные и «удалённые у меня» в общий список не попадают; новое сообщение вернёт чат.
    final all = [
      for (final c in everything)
        if (!hiddenFromList(c, settingsOf(c))) c,
    ];
    final archived = [
      for (final c in everything)
        if (inArchive(c, settingsOf(c))) c,
    ];

    // Непрочитанные по вкладке: заглушённые чаты не считаем, они не должны
    // звать внимание и через бейдж.
    int unread(_Tab tab) => all
        .where(
          (c) =>
              _tabOf(c) == tab &&
              c.unreadCount > 0 &&
              !chatNotifyOf(ref, c.id).isMuted,
        )
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
                  color: AppColors.primaryTint,
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                ),
                child: Text(
                  '$n',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onPrimary,
                  ),
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
          if (archived.isNotEmpty)
            IconButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const _ArchivedScreen(),
                ),
              ),
              tooltip: 'Архив',
              icon: Badge(
                isLabelVisible: archived.any((c) => c.unreadCount > 0),
                smallSize: 8,
                child: const Icon(Icons.archive_outlined),
              ),
            ),
          // Лупа ищет то, что относится к текущей вкладке: людей и чаты на
          // «Личных» и «Группах», каналы — на «Каналах».
          IconButton(
            onPressed: () => context.push(
              current == _Tab.channels ? Routes.channels : Routes.chatSearch,
            ),
            tooltip: current == _Tab.channels
                ? 'Найти каналы'
                : 'Найти человека',
            icon: Icon(
              current == _Tab.channels ? Icons.travel_explore : Icons.search,
            ),
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
      // Scaffold поднимает кнопку только над системной полосой, а плавающая
      // панель вкладок лежит поверх тела — поднимаем сами.
      floatingActionButton: fab == null
          ? null
          : Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.paddingOf(context).bottom,
              ),
              child: fab,
            ),
      body: conversations.when(
        loading: () => const LoadingView(),
        error: (_, _) => StateMessage.error(
          title: 'Не удалось загрузить чаты',
          onAction: () => ref.invalidate(conversationsProvider),
        ),
        data: (_) => TabBarView(
          controller: _tabs,
          children: [
            for (final tab in _Tab.values)
              RefreshIndicator(
                onRefresh: () => ref.refresh(conversationsProvider.future),
                child: _list(
                  context,
                  [
                    for (final c in all)
                      if (_tabOf(c) == tab) c,
                  ],
                  tab,
                  showEncryptionNotice:
                      tab == _Tab.direct && !encryptionEnabled,
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
      // Снизу — место под кнопку «Группа/Канал» и плавающую панель вкладок
      // (её высота уже в MediaQuery.padding).
      padding: EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        12,
        AppSpacing.gutter,
        80 + MediaQuery.paddingOf(context).bottom,
      ),
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
                const Expanded(
                  child: Text('Найти каналы: новости, наука, еда, мемы…'),
                ),
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
                _Tab.direct =>
                  'Откройте профиль человека и нажмите «Написать».',
                _Tab.groups => 'Создайте группу кнопкой внизу.',
                _Tab.channels =>
                  'Загляните в каталог — подписка в одно касание.',
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

/// Архив: чаты, убранные из списка. Нажатие открывает чат, долгое нажатие
/// возвращает его в список.
class _ArchivedScreen extends ConsumerWidget {
  const _ArchivedScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings =
        ref.watch(chatSettingsProvider).asData?.value ??
        const <String, ChatSettings>{};
    final myId = ref.watch(currentUserProvider)?.id;
    final items = [
      for (final c
          in ref.watch(conversationsProvider).value ?? const <Conversation>[])
        if (inArchive(c, settings[c.id] ?? ChatSettings.none)) c,
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Архив')),
      body: items.isEmpty
          ? const StateMessage(
              title: 'В архиве пусто',
              text: 'Архивировать чат можно в меню ⋮ внутри него.',
              icon: Icons.archive_outlined,
            )
          : ListView(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.gutter,
                12,
                AppSpacing.gutter,
                24 + MediaQuery.paddingOf(context).bottom,
              ),
              children: [
                for (final c in items) ...[
                  _ConversationTile(
                    conversation: c,
                    myId: myId,
                    notify: chatNotifyOf(ref, c.id),
                    onLongPress: () async {
                      await setChatArchived(ref, c.id, false);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Чат возвращён в список'),
                          ),
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
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
        : conversation.isDirect ||
              conversation.isChannel ||
              last.senderName == null
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
            Consumer(
              builder: (context, ref, child) {
                final online =
                    ref
                        .watch(peerPresenceProvider(conversation.id))
                        .value
                        ?.online ??
                    false;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    child!,
                    if (online)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 13,
                          height: 13,
                          decoration: BoxDecoration(
                            color: AppColors.success,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.card, width: 2),
                          ),
                        ),
                      ),
                  ],
                );
              },
              child: UserAvatar(
                name: conversation.displayName,
                url: conversation.peerAvatarUrl,
                radius: 22,
              ),
            )
          else if (conversation.isChannel)
            ChannelAvatar(url: conversation.peerAvatarUrl, radius: 22)
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
                color: AppColors.primaryTint,
                size: 20,
              ),
            ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        conversation.displayName,
                        style: Theme.of(context).textTheme.titleLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (conversation.isDirect)
                      Consumer(
                        builder: (context, ref, _) {
                          final presence = ref
                              .watch(peerPresenceProvider(conversation.id))
                              .value;
                          final label = presence?.label(DateTime.now());
                          if (label == null) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Text(
                              label,
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: 12,
                                color: presence!.online
                                    ? AppColors.success
                                    : AppColors.textFaint,
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                if (!conversation.isChannel)
                  Consumer(
                    builder: (context, ref, previewRow) {
                      final typing =
                          ref
                              .watch(typingEntriesProvider(conversation.id))
                              .value ??
                          const <TypingEntry>[];
                      final text = typingLabel(
                        typing,
                        direct: conversation.isDirect,
                      );
                      if (text.isEmpty) return previewRow!;
                      return Text(
                        text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.primaryTint,
                        ),
                      );
                    },
                    child: _previewRow(context, last, preview),
                  )
                else
                  _previewRow(context, last, preview),
              ],
            ),
          ),
          ..._trailing(),
        ],
      ),
    );
  }

  Widget _previewRow(BuildContext context, ChatMessage? last, String preview) =>
      Row(
        children: [
          // Своё последнее сообщение — с галочками, как в переписке.
          if (last != null && last.senderId == myId) ...[
            Icon(
              last.status == MessageStatus.read ? Icons.done_all : Icons.done,
              size: 15,
              color: last.status == MessageStatus.read
                  ? AppColors.primaryTint
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
      );

  List<Widget> _trailing() => [
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
          color: notify.isMuted ? AppColors.hairStrong : AppColors.primaryTint,
          borderRadius: BorderRadius.circular(AppRadius.chip),
        ),
        child: Text(
          '${conversation.unreadCount}',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: notify.isMuted ? AppColors.text : AppColors.onPrimary,
          ),
        ),
      ),
    ],
  ];
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
