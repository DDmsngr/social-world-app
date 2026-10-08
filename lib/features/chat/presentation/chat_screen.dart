import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/debug/app_log.dart';
import '../../../core/push/push_service.dart';
import '../../../core/router/app_router.dart';
import '../../../core/shortcuts/home_shortcut.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/sw_widgets.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../calls/call_controller.dart';
import '../../calls/call_kit.dart';
import '../../calls/call_log.dart';
import '../domain/day_label.dart';
import '../domain/timeline.dart';
import '../live_location/live_location.dart';
import '../live_location/live_location_screen.dart';
import '../domain/entities/chat_message.dart';
import '../domain/entities/chat_meta.dart';
import '../domain/entities/conversation.dart';
import 'conversations_screen.dart';
import 'providers/chat_extras_providers.dart';
import 'providers/chat_pins_providers.dart';
import 'providers/chat_notify_providers.dart';
import 'providers/chat_providers.dart';
import 'providers/hidden_messages_provider.dart';
import 'widgets/bookmarks_sheet.dart';
import '../../../core/errors/friendly_error.dart';
import 'chat_looks.dart';
import 'providers/chat_settings_providers.dart';
import 'providers/chat_typing_providers.dart';
import 'widgets/chat_look_sheets.dart';
import 'widgets/chat_composer.dart';
import 'widgets/chat_notify_sheet.dart';
import 'widgets/message_bubble.dart';
import 'widgets/message_menu.dart';
import 'widgets/pinned_bar.dart';
import 'widgets/reaction_chips.dart';
import 'widgets/swipe_to_reply.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.peerName,
    this.jumpToMessageId,
  });

  final String conversationId;

  /// Открыть чат сразу на этом сообщении (из закладок и закрепов).
  final String? jumpToMessageId;

  /// Имя из списка — показывается, пока карточка чата не загрузилась.
  final String peerName;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen>
    with WidgetsBindingObserver {
  late final PushService _push;

  /// Сообщение, по которому открыто меню, — подсвечено, пока меню открыто.
  String? _selectedId;

  /// Ответ, который сейчас набирается: показан над полем ввода.
  ChatReply? _replyTo;

  final _scroll = ScrollController();

  /// Плашка с датой поверх ленты, пока её листают (как в Telegram).
  final _listBox = GlobalKey();
  List<ChatMessage> _shown = const [];
  String? _floatingDay;
  bool _floatingVisible = false;
  Timer? _floatingHide;
  DateTime _floatingChecked = DateTime(0);
  final _itemKeys = <String, GlobalKey>{};
  int _pinCursor = 0;
  String? _pendingJump;

  /// Подводит ленту к сообщению и ненадолго подсвечивает его. Лента ленивая:
  /// пока сообщение не построено, прыгаем по оценке положения и пробуем снова.
  Future<void> _jumpTo(String messageId, List<ChatMessage> items) async {
    final index = items.indexWhere((m) => m.id == messageId);
    if (index < 0) {
      await _showOutsideHistory(messageId);
      return;
    }
    for (var attempt = 0; attempt < 8; attempt++) {
      if (!mounted) return;
      final target = _itemKeys[messageId]?.currentContext;
      if (target != null && target.mounted) {
        await Scrollable.ensureVisible(
          target,
          alignment: 0.4,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
        if (!mounted) return;
        _flash(messageId);
        return;
      }
      if (!_scroll.hasClients) return;
      final max = _scroll.position.maxScrollExtent;
      final fromBottom = items.length - 1 - index;
      _scroll.jumpTo((max * fromBottom / items.length).clamp(0.0, max));
      await WidgetsBinding.instance.endOfFrame;
    }
    await _showOutsideHistory(messageId);
  }

  void _flash(String messageId) {
    setState(() => _selectedId = messageId);
    Future<void>.delayed(const Duration(milliseconds: 1400), () {
      if (mounted && _selectedId == messageId) setState(() => _selectedId = null);
    });
  }

  /// Сообщение старше загруженной истории: показываем его отдельным окном.
  Future<void> _showOutsideHistory(String messageId) async {
    try {
      final found = await ref
          .read(chatRepositoryProvider)
          .loadMessagesByIds(widget.conversationId, [messageId]);
      if (!mounted) return;
      final text = found.isEmpty ? 'Сообщение не найдено' : found.first.preview;
      await showDialog<void>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Старое сообщение'),
          content: SingleChildScrollView(child: SelectableText(text)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialog).pop(),
              child: const Text('Закрыть'),
            ),
          ],
        ),
      );
    } catch (error) {
      AppLog.add('Старое сообщение не открылось: $error');
    }
  }

  String _nameOf(ChatMessage message, String myId, Conversation? info) {
    if (message.senderId == myId) {
      return ref.read(currentUserProvider)?.displayName ?? 'Вы';
    }
    return message.senderName ??
        (info != null && info.isDirect ? info.peerName : null) ??
        'Пользователь';
  }

  void _startReply(ChatMessage message, String myId) {
    final info = ref.read(conversationProvider(widget.conversationId)).value;
    setState(
      () => _replyTo = ChatReply.of(
        message,
        senderName: _nameOf(message, myId, info),
      ),
    );
  }

  /// После сворачивания приложения сокеты нередко «мёртвые»: переподключаем
  /// переписку сами, а не ждём, пока человек выйдет и зайдёт снова. Старые
  /// сообщения при этом остаются на экране.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // Чат остался открытым, пока приложение было свёрнуто: пришедшее за это
    // время уведомление уже прочитано здесь — убираем его из шторки (раньше
    // оно уходило, только если войти через само уведомление).
    _push.clearConversation(widget.conversationId);
    _markRead();
    ref.invalidate(messagesProvider(widget.conversationId));
    ref.invalidate(conversationProvider(widget.conversationId));
    ref.invalidate(scheduledMessagesProvider(widget.conversationId));
  }

  Future<bool> _openMenu(
    BuildContext context,
    ChatMessage message,
    String myId,
  ) async {
    setState(() => _selectedId = message.id);
    try {
      return await showMessageMenu(
        context,
        ref,
        message: message,
        myId: myId,
        conversation: ref
            .read(conversationProvider(widget.conversationId))
            .value,
        onReply: (message) => _startReply(message, myId),
        // Реакцию можно поставить только на дошедшее сообщение.
        myReaction: _myReaction(message.id),
        onReact: message.status == MessageStatus.failed ||
                message.status == MessageStatus.sending
            ? null
            : (emoji) => _react(message.id, emoji),
      );
    } finally {
      if (mounted) setState(() => _selectedId = null);
    }
  }

  Future<void> _quickReact(
    BuildContext context,
    ChatMessage message,
    String myId,
  ) async {
    setState(() => _selectedId = message.id);
    try {
      final emoji = await showReactionPicker(
        context,
        mine: message.senderId == myId,
        myReaction: _myReaction(message.id),
      );
      if (emoji != null) await _react(message.id, emoji);
    } finally {
      if (mounted) setState(() => _selectedId = null);
    }
  }

  String? _myReaction(String messageId) {
    final list = ref.read(chatReactionsProvider(widget.conversationId)).value?[messageId];
    for (final r in list ?? const <ReactionCount>[]) {
      if (r.mine) return r.emoji;
    }
    return null;
  }

  Future<void> _react(String messageId, String emoji) async {
    HapticFeedback.selectionClick();
    try {
      await toggleReaction(ref, widget.conversationId, messageId, emoji);
    } catch (error) {
      AppLog.add('Реакция не поставилась: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось поставить реакцию')),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _push = ref.read(pushServiceProvider)
      ..enterChat(widget.conversationId)
      ..clearConversation(widget.conversationId);
    _pendingJump = widget.jumpToMessageId;
    _markRead();
    unawaited(_warnIfPeerKeyChanged());
  }

  Future<void> _warnIfPeerKeyChanged() async {
    try {
      final changed = await ref
          .read(chatRepositoryProvider)
          .peerKeyChanged(widget.conversationId);
      if (!changed || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 10),
          content: const Text(
            'Ключ шифрования собеседника сменился. Так бывает после '
            'переустановки приложения, но может быть и подмена.',
          ),
          action: SnackBarAction(label: 'Проверить', onPressed: _showSecurityCode),
        ),
      );
    } catch (error) {
      AppLog.add('Проверка ключа собеседника: $error');
    }
  }

  void _markRead() {
    ref
        .read(chatRepositoryProvider)
        .markRead(widget.conversationId)
        .then((_) => ref.invalidate(conversationsProvider))
        .catchError((Object error) => AppLog.add('Отметка прочтения: $error'));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _floatingHide?.cancel();
    _scroll.dispose();
    _push.leaveChat(widget.conversationId);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(messagesProvider(widget.conversationId));
    final conversation = ref.watch(conversationProvider(widget.conversationId));
    final info = conversation.value;
    final myId = ref.watch(currentUserProvider)?.id ?? 'local-user';
    final isDirect = info?.isDirect ?? true;
    final hidden = ref.watch(hiddenMessagesProvider);
    final settings = chatSettingsOf(ref, widget.conversationId);

    // Пока экран открыт, входящие сразу считаются прочитанными.
    ref.listen(messagesProvider(widget.conversationId), (previous, next) {
      final before = previous?.value?.length ?? 0;
      if ((next.value?.length ?? 0) > before && before > 0) {
        _markRead();
        // Отложенное могло как раз уйти — список «запланировано» устарел.
        ref.invalidate(scheduledMessagesProvider(widget.conversationId));
      }
    });

    final reactions =
        ref.watch(chatReactionsProvider(widget.conversationId)).value ?? const {};
    final pinned = ref.watch(pinnedMessagesProvider(widget.conversationId)).value ?? const <ChatMessage>[];
    final hasBookmarks = ref
            .watch(myBookmarksProvider)
            .value
            ?.any((b) => b.conversationId == widget.conversationId) ??
        false;
    final canPin = info != null && (info.isDirect || info.isOwner);
    // Шапка по макету «Диалог»: аватар, имя и «в сети / был(а) …».
    final presence = isDirect
        ? ref.watch(peerPresenceProvider(widget.conversationId)).value
        : null;
    // Кто-то пишет — вместо «в сети» смешная фраза («подбирает слова…»).
    final typing = ref.watch(typingEntriesProvider(widget.conversationId)).value ?? const <TypingEntry>[];
    final typingText = typingLabel(typing, direct: isDirect);
    final liveShares = ref.watch(liveSharesProvider(widget.conversationId)).value ?? const <LiveShare>[];
    // Звонки бывают только в личных переписках.
    final calls = isDirect
        ? ref.watch(chatCallsProvider(widget.conversationId)).value ?? const <CallLogEntry>[]
        : const <CallLogEntry>[];
    // Собеседник только что писал или печатал — он в сети, даже если отметка
    // присутствия на сервере ещё не догнала (обновляется раз в минуту):
    // раньше Вика писала, а в шапке висело «был(а) 13 мин назад».
    final now = DateTime.now();
    final peerLastMessage = isDirect
        ? messages.value?.lastWhere((m) => m.senderId != myId, orElse: () => _noMessage).sentAt
        : null;
    final peerActive = typing.isNotEmpty ||
        (peerLastMessage != null && now.difference(peerLastMessage) < const Duration(minutes: 2));
    final subtitle = typingText.isNotEmpty
        ? typingText
        : info != null && !isDirect
        ? membersLabel(info.memberCount)
        : peerActive
        ? 'в сети'
        : presence?.label(now);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: InkWell(
          onTap: info == null
              ? null
              : isDirect
              ? (info.peerId == null ? null : () => openProfile(context, info.peerId!))
              : () => context.push(
                  '${Routes.chats}/${widget.conversationId}/info',
                ),
          child: Row(
            children: [
              if (isDirect)
                UserAvatar(
                  name: info?.displayName ?? widget.peerName,
                  url: info?.peerAvatarUrl,
                  radius: 19,
                )
              else
                CircleAvatar(
                  radius: 19,
                  backgroundColor: AppColors.card,
                  child: Icon(Icons.group_outlined, size: 18, color: AppColors.primaryTint),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      info?.displayName ?? widget.peerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: typingText.isNotEmpty || (presence?.online ?? false)
                              ? AppColors.primaryTint
                              : AppColors.textDim,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        titleTextStyle: Theme.of(context).textTheme.titleLarge,
        actions: [
          if (hasBookmarks)
            IconButton(
              onPressed: () async {
                final id = await showChatBookmarks(context, widget.conversationId);
                if (id != null && mounted) {
                  _jumpTo(id, ref.read(messagesProvider(widget.conversationId)).value ?? const []);
                }
              },
              tooltip: 'Закладки',
              icon: const Icon(Icons.bookmarks_outlined),
            ),
          // В личном чате место в шапке — звонкам; уведомления и код
          // безопасности там в меню «Ещё».
          if (!isDirect)
            IconButton(
              onPressed: () => showChatNotifySheet(
                context,
                widget.conversationId,
                info?.displayName ?? widget.peerName,
              ),
              tooltip: 'Уведомления',
              icon: Icon(_notifyIcon(chatNotifyOf(ref, widget.conversationId))),
            ),
          if (info != null && isDirect && info.peerId != null && CallKit.supported) ...[
            IconButton(
              onPressed: () => _call(info, video: true),
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 38, height: 40),
              iconSize: 22,
              tooltip: 'Видеозвонок',
              icon: const Icon(Icons.videocam_outlined),
            ),
            IconButton(
              onPressed: () => _call(info, video: false),
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 38, height: 40),
              iconSize: 22,
              tooltip: 'Позвонить',
              icon: const Icon(Icons.call_outlined),
            ),
          ] else if (info != null && !isDirect)
            IconButton(
              onPressed: () => context.push(
                '${Routes.chats}/${widget.conversationId}/info',
              ),
              tooltip: 'О группе',
              icon: const Icon(Icons.info_outline),
            ),
          PopupMenuButton<String>(
            tooltip: 'Ещё',
            padding: const EdgeInsets.symmetric(horizontal: 6),
            iconSize: 22,
            color: AppColors.ink2,
            onSelected: (value) => _onMenu(value, info?.displayName ?? widget.peerName, isDirect, info?.peerAvatarUrl, settings),
            itemBuilder: (_) => [
              if (isDirect) ...[
                PopupMenuItem(
                  value: 'notify',
                  child: Row(
                    children: [
                      Expanded(child: Text('Уведомления')),
                      Icon(_notifyIcon(chatNotifyOf(ref, widget.conversationId)), size: 20),
                    ],
                  ),
                ),
                if (info != null) const PopupMenuItem(value: 'security', child: Text('Код безопасности')),
              ],
              const PopupMenuItem(value: 'sound', child: Text('Звук чата')),
              const PopupMenuItem(value: 'wallpaper', child: Text('Фон чата')),
              if (HomeShortcut.supported)
                const PopupMenuItem(value: 'shortcut', child: Text('Ярлык на рабочий стол')),
              PopupMenuItem(
                value: 'archive',
                child: Text(settings.archivedAt != null ? 'Вернуть из архива' : 'В архив'),
              ),
              const PopupMenuItem(value: 'delete', child: Text('Удалить чат')),
            ],
          ),        ],
      ),
      body: ChatBackground(
        wallpaper: settings.wallpaper,
        child: Column(
        children: [
          if (isDirect)
            WallpaperOfferBar(
              conversationId: widget.conversationId,
              peerName: info?.displayName ?? widget.peerName,
            ),
          if (liveShares.isNotEmpty)
            _LiveBar(
              shares: liveShares,
              myId: myId,
              peerName: info?.displayName,
              onTap: () => Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute<void>(
                  builder: (_) => LiveLocationScreen(conversationId: widget.conversationId),
                ),
              ),
            ),
          if (pinned.isNotEmpty)
            PinnedBar(
              pins: pinned,
              index: _pinCursor,
              onTap: () {
                final i = _pinCursor.clamp(0, pinned.length - 1);
                _jumpTo(pinned[i].id, ref.read(messagesProvider(widget.conversationId)).value ?? const []);
                // Следующее нажатие — к следующему закрепу.
                setState(() => _pinCursor = (i + 1) % pinned.length);
              },
              onUnpin: canPin
                  ? () async {
                      final i = _pinCursor.clamp(0, pinned.length - 1);
                      try {
                        await setPinned(ref, widget.conversationId, pinned[i].id, pinned: false);
                      } catch (error) {
                        AppLog.add('Открепить: $error');
                      }
                    }
                  : null,
            ),
          if (info != null && !isDirect) const _PlainTextNotice(),
          Expanded(
            child: messages.when(
              // Уже показанные сообщения не прячем за спиннером при
              // переподключении и ошибках сети: переписка остаётся на месте,
              // а о связи говорит тонкая полоска сверху.
              skipLoadingOnReload: true,
              skipLoadingOnRefresh: true,
              skipError: true,
              loading: () => _SlowLoading(
                onRetry: () =>
                    ref.invalidate(messagesProvider(widget.conversationId)),
              ),
              error: (error, _) => _ErrorView(
                keysMissing: error.toString().contains('ключи'),
                onRetry: () =>
                    ref.invalidate(messagesProvider(widget.conversationId)),
              ),
              data: (all) {
                final cleared = settings.clearedAt;
                final items = hidden.isEmpty && cleared == null
                    ? all
                    : [
                        for (final m in all)
                          if (!hidden.contains(m.id) && (cleared == null || m.sentAt.isAfter(cleared))) m,
                      ];
                final entries = mergeCallsIntoTimeline(items, [
                  for (final c in calls)
                    if (cleared == null || c.createdAt.isAfter(cleared)) c,
                ]);
                if (entries.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.gutter),
                      child: Text(
                        isDirect
                            ? 'Напишите первое сообщение. Переписка защищена '
                                  'сквозным шифрованием.'
                            : 'Сообщений пока нет.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  );
                }
                // reverse: новые снизу, и лента сама держится у последнего
                // сообщения при входящих.
                if (_pendingJump != null) {
                  final id = _pendingJump!;
                  _pendingJump = null;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _jumpTo(id, items);
                  });
                }
                _shown = items;
                final list = ListView.builder(
                  controller: _scroll,
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.gutter,
                    14,
                    AppSpacing.gutter,
                    14,
                  ),
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final position = entries.length - 1 - index;
                    final entry = entries[position];
                    // Первое сообщение (или звонок) дня — с подписью дня над ним.
                    final newDay = position == 0 || !sameDay(entries[position - 1].at, entry.at);
                    final call = entry.call;
                    if (call != null) {
                      final tile = _CallLogTile(
                        call: call,
                        mine: call.callerId == myId,
                        onTap: info == null || info.peerId == null ? null : () => _call(info, video: call.video),
                      );
                      if (!newDay) return tile;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(child: _DayChip(chatDayLabel(entry.at, DateTime.now()))),
                          tile,
                        ],
                      );
                    }
                    final message = entry.message!;
                    final mine = message.senderId == myId;
                    final item = KeyedSubtree(
                      key: _itemKeys.putIfAbsent(message.id, GlobalKey.new),
                      child: Semantics(
                      customSemanticsActions: {
                        const CustomSemanticsAction(
                          label: 'Действия с сообщением',
                        ): () => _openMenu(context, message, myId),
                      },
                      child: SwipeToReply(
                        enabled: !(info?.closed ?? false) &&
                            message.signatureValid != false &&
                            message.status != MessageStatus.failed,
                        onReply: () => _startReply(message, myId),
                        child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        // Короткий тап в личной переписке — реакции, долгий —
                        // выделение и меню. Реакцию можно поставить только на
                        // дошедшее сообщение.
                        onTap: isDirect &&
                                message.status != MessageStatus.failed &&
                                message.status != MessageStatus.sending
                            ? () => _quickReact(context, message, myId)
                            : null,
                        onLongPress: () => _openMenu(context, message, myId),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          decoration: BoxDecoration(
                            color: _selectedId == message.id
                                ? AppColors.hair
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(
                              AppRadius.card,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: mine
                                ? CrossAxisAlignment.end
                                : CrossAxisAlignment.start,
                            children: [
                              MessageBubble(
                                message: message,
                                mine: mine,
                                showSender: !isDirect && !mine,
                                onMediaMore: (viewerContext) =>
                                    _openMenu(viewerContext, message, myId),
                                onQuoteTap: message.replyTo == null
                                    ? null
                                    : () => _jumpTo(message.replyTo!.messageId, items),
                              ),
                              ReactionChips(
                                reactions: reactions[message.id] ?? const [],
                                mine: mine,
                                onTap: (emoji) => _react(message.id, emoji),
                              ),
                            ],
                          ),
                        ),
                        ),
                      ),
                      ),
                    );
                    if (!newDay) return item;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(child: _DayChip(chatDayLabel(message.sentAt, DateTime.now()))),
                        item,
                      ],
                    );
                  },
                );
                return Stack(
                  key: _listBox,
                  children: [
                    NotificationListener<ScrollNotification>(
                      onNotification: _onListScroll,
                      child: list,
                    ),
                    Positioned(
                      top: 8,
                      left: 0,
                      right: 0,
                      child: IgnorePointer(
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 200),
                          opacity: _floatingVisible && _floatingDay != null ? 1 : 0,
                          child: Center(child: _DayChip(_floatingDay ?? '')),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          if (messages.hasValue && (messages.isLoading || messages.hasError))
            _ConnectionBanner(
              onRetry: () =>
                  ref.invalidate(messagesProvider(widget.conversationId)),
            ),
          if (info?.closed ?? false)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  'Чат закрыт — квест завершён',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            )
          // Пока нет ключей собеседника, зашифровать нечем: вместо поля, которое
          // гарантированно выдаст «не удалось отправить», — только объяснение
          // над ним (_ErrorView).
          else if (!(messages.hasError &&
              messages.error.toString().contains('ключи')))
            ChatComposer(
              conversationId: widget.conversationId,
              isDirect: isDirect,
              peerName: info?.peerName,
              replyTo: _replyTo,
              onReplyCleared: () => setState(() => _replyTo = null),
            ),
        ],
      ),
      ),
    );
  }

  /// Листают — показываем дату верхнего видимого сообщения; перестали —
  /// через секунду плашка уходит.
  bool _onListScroll(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification) {
      final now = DateTime.now();
      if (now.difference(_floatingChecked) > const Duration(milliseconds: 120)) {
        _floatingChecked = now;
        final day = _topVisibleDay();
        if (day != _floatingDay || !_floatingVisible) {
          setState(() {
            _floatingDay = day;
            _floatingVisible = day != null;
          });
        }
      }
      _floatingHide?.cancel();
    } else if (notification is ScrollEndNotification) {
      _floatingHide?.cancel();
      _floatingHide = Timer(const Duration(seconds: 1), () {
        if (mounted && _floatingVisible) setState(() => _floatingVisible = false);
      });
    }
    return false;
  }

  String? _topVisibleDay() {
    final box = _listBox.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return null;
    final top = box.localToGlobal(Offset.zero).dy;
    ChatMessage? best;
    var bestY = double.infinity;
    for (final message in _shown) {
      final itemBox = _itemKeys[message.id]?.currentContext?.findRenderObject() as RenderBox?;
      if (itemBox == null || !itemBox.attached) continue;
      final y = itemBox.localToGlobal(Offset.zero).dy;
      // Верхнее из тех, чей низ ещё виден.
      if (y + itemBox.size.height > top && y < bestY) {
        bestY = y;
        best = message;
      }
    }
    return best == null ? null : chatDayLabel(best.sentAt, DateTime.now());
  }

  IconData _notifyIcon(ChatNotify notify) => switch (notify) {
    final n when n.isMuted => Icons.notifications_off_outlined,
    final n when n.mode == NotifyMode.vibrate => Icons.vibration,
    final n when n.mode == NotifyMode.silent => Icons.notifications_none,
    _ => Icons.notifications_active_outlined,
  };

  void _call(Conversation info, {required bool video}) {
    final calls = ref.read(callControllerProvider);
    if (calls.busy) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Уже идёт звонок')),
      );
      return;
    }
    unawaited(
      calls.dial(
        conversationId: widget.conversationId,
        peerId: info.peerId!,
        peerName: info.displayName,
        peerAvatarUrl: info.peerAvatarUrl,
        video: video,
      ),
    );
  }

  Future<void> _onMenu(
    String value,
    String title,
    bool isDirect,
    String? avatarUrl,
    ChatSettings settings,
  ) async {
    switch (value) {
      case 'notify':
        await showChatNotifySheet(context, widget.conversationId, title);
      case 'security':
        _showSecurityCode();
      case 'sound':
        await showChatSoundSheet(context, widget.conversationId);
      case 'wallpaper':
        await showChatWallpaperSheet(
          context,
          widget.conversationId,
          direct: isDirect,
          peerName: title,
        );
      case 'shortcut':
        final pinned = await HomeShortcut.pinChat(
          conversationId: widget.conversationId,
          title: title,
          avatarUrl: isDirect ? avatarUrl : null,
        );
        if (!pinned && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Этот телефон не даёт добавлять ярлыки на рабочий стол')),
          );
        }
      case 'archive':
        final archive = settings.archivedAt == null;
        try {
          await setChatArchived(ref, widget.conversationId, archive);
        } catch (error) {
          AppLog.add('Архив чата: $error');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(friendlyError(error, fallback: 'Не удалось выполнить'))),
            );
          }
          return;
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(archive ? 'Чат в архиве' : 'Чат возвращён из архива')),
        );
        if (archive) context.canPop() ? context.pop() : context.go(Routes.chats);
      case 'delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Удалить чат?'),
            content: Text(
              isDirect
                  ? 'Переписка исчезнет только у вас. У $title всё останется, а новое '
                        'сообщение вернёт чат в список — уже без старой истории.'
                  : 'История исчезнет только у вас. Из группы вы не выходите.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
              TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Удалить')),
            ],
          ),
        );
        if (ok != true || !mounted) return;
        try {
          await clearChatForMe(ref, widget.conversationId);
        } catch (error) {
          AppLog.add('Удаление чата: $error');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(friendlyError(error, fallback: 'Не удалось удалить'))),
            );
          }
          return;
        }
        if (mounted) context.canPop() ? context.pop() : context.go(Routes.chats);
    }
  }
  Future<void> _showSecurityCode() async {
    final repository = ref.read(chatRepositoryProvider);
    final code = repository.securityCode(widget.conversationId);
    final changed = await repository
        .peerKeyChanged(widget.conversationId)
        .catchError((Object _) => false);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context, useRootNavigator: true,
      backgroundColor: AppColors.ink2,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            8,
            AppSpacing.gutter,
            28,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Код безопасности', style: AppTypography.serif(28)),
              const SizedBox(height: 10),
              Text(
                'Сверьте этот код с собеседником голосом или при встрече. '
                'Совпадение исключает подмену ключей.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 18),
              GlassCard(
                child: FutureBuilder<String>(
                  future: code,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return const Text('Код пока недоступен');
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    return SelectableText(
                      snapshot.data!,
                      style: TextStyle(
                        color: AppColors.primaryTint,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.4,
                      ),
                    );
                  },
                ),
              ),
              if (changed) ...[
                const SizedBox(height: 16),
                Text(
                  'Ключ собеседника сменился, и сообщения ему пока не '
                  'отправляются. Спросите, переустанавливал ли он приложение, '
                  'и сверьте новый код. Если код совпал, примите ключ.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    await repository.acceptPeerKey(widget.conversationId);
                    navigator.pop();
                  },
                  child: const Text('Код совпал, принять новый ключ'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Группы не шифруются сквозным шифрованием — это видно сразу.
class _PlainTextNotice extends StatelessWidget {
  const _PlainTextNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.gutter,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.hair)),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_open, size: 14, color: AppColors.textFaint),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Групповой чат без сквозного шифрования',
              style: TextStyle(fontSize: 12, color: AppColors.textFaint),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.keysMissing, required this.onRetry});

  final bool keysMissing;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.gutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              keysMissing
                  ? 'Собеседник ещё не заходил в новую версию приложения, '
                        'поэтому зашифровать для него сообщение пока нечем. '
                        'Как только он обновится и откроет приложение, здесь '
                        'можно будет переписываться. Группы работают и без этого.'
                  : 'Не удалось загрузить переписку',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            TextButton(onPressed: onRetry, child: const Text('Повторить')),
          ],
        ),
      ),
    );
  }
}

/// Человекочитаемая подпись состояния доставки.
String messageStatusLabel(MessageStatus status) => switch (status) {
  MessageStatus.sending => 'отправляется',
  MessageStatus.sent => 'отправлено',
  MessageStatus.delivered => 'доставлено',
  MessageStatus.read => 'прочитано',
  MessageStatus.failed => 'не ушло',
};

/// Первая загрузка переписки. Если она тянется дольше нескольких секунд, это
/// уже не «грузится», а «завис»: вместо вечного кружка — понятная подпись и
/// кнопка, которая переподключает чат.
class _SlowLoading extends StatefulWidget {
  const _SlowLoading({required this.onRetry});

  final VoidCallback onRetry;

  @override
  State<_SlowLoading> createState() => _SlowLoadingState();
}

class _SlowLoadingState extends State<_SlowLoading> {
  static const _patience = Duration(seconds: 10);

  Timer? _timer;
  var _slow = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(_patience, () {
      if (mounted) setState(() => _slow = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: AppColors.primaryTint,
            ),
          ),
          if (_slow) ...[
            const SizedBox(height: 18),
            Text(
              'Долго подключаемся к чату',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                setState(() => _slow = false);
                _timer?.cancel();
                _timer = Timer(_patience, () {
                  if (mounted) setState(() => _slow = true);
                });
                widget.onRetry();
              },
              child: const Text('Переподключить'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Тонкая полоска над полем ввода: связь с чатом потеряна, идёт
/// переподключение. Сообщения на экране остаются, писать по-прежнему можно.
class _ConnectionBanner extends StatelessWidget {
  const _ConnectionBanner({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      child: InkWell(
        onTap: onRetry,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.8,
                  color: AppColors.primaryTint,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Подключаемся… Нажмите, чтобы повторить',
                  style: TextStyle(fontSize: 12, color: AppColors.textDim),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final _noMessage = ChatMessage(id: '', conversationId: '', senderId: '', sentAt: DateTime(2000));

/// Плашка под шапкой, пока кто-то в чате транслирует геопозицию. Тап — карта.
class _LiveBar extends StatelessWidget {
  const _LiveBar({required this.shares, required this.myId, required this.onTap, this.peerName});

  final List<LiveShare> shares;
  final String myId;
  final String? peerName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final mine = shares.where((s) => s.userId == myId).firstOrNull;
    final others = shares.where((s) => s.userId != myId).toList();
    final text = switch ((mine, others.length)) {
      (final m?, 0) => 'Вы транслируете геопозицию · ${liveRemainingLabel(m, now)}',
      (null, 1) => '${peerName ?? 'Собеседник'} делится геопозицией · ${liveRemainingLabel(others.first, now)}',
      (_, final n) => mine != null ? 'Геопозицией делятся: вы и ещё $n' : 'Геопозицией делятся $n',
    };
    return Material(
      color: AppColors.geo.withValues(alpha: 0.14),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.share_location, color: AppColors.geo, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis)),
              Text('Карта', style: TextStyle(color: AppColors.geo, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Звонок в ленте: с чьей стороны был вызов, состоялся ли и сколько длился.
/// Тап — перезвонить тем же видом звонка.
class _CallLogTile extends StatelessWidget {
  const _CallLogTile({required this.call, required this.mine, this.onTap});

  final CallLogEntry call;
  final bool mine;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final failed = !call.talked && call.status != 'ringing' && call.status != 'active';
    final color = failed && !mine ? AppColors.danger : AppColors.primaryTint;
    final icon = call.video
        ? Icons.videocam_outlined
        : failed && !mine
        ? Icons.call_missed
        : mine
        ? Icons.call_made
        : Icons.call_received;
    final time = '${call.createdAt.hour.toString().padLeft(2, '0')}:${call.createdAt.minute.toString().padLeft(2, '0')}';
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Material(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadius.card),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 16, 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: color.withValues(alpha: 0.15),
                    child: Icon(icon, size: 20, color: color),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(callLogTitle(call, mine: mine), style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(
                        '${callLogStatus(call, mine: mine)} · $time',
                        style: TextStyle(fontSize: 13, color: failed && !mine ? AppColors.danger : AppColors.textDim),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Подпись дня в ленте и плашка с датой при прокрутке.
class _DayChip extends StatelessWidget {
  const _DayChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          child: Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ),
      ),
    );
  }
}