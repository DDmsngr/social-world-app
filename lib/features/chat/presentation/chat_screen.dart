import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/debug/app_log.dart';
import '../../../core/push/push_service.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/sw_widgets.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../domain/entities/chat_message.dart';
import '../domain/entities/chat_meta.dart';
import '../domain/entities/conversation.dart';
import 'conversations_screen.dart';
import 'providers/chat_notify_providers.dart';
import 'providers/chat_providers.dart';
import 'providers/hidden_messages_provider.dart';
import 'widgets/chat_composer.dart';
import 'widgets/chat_notify_sheet.dart';
import 'widgets/message_bubble.dart';
import 'widgets/message_menu.dart';
import 'widgets/swipe_to_reply.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.peerName,
  });

  final String conversationId;

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
      );
    } finally {
      if (mounted) setState(() => _selectedId = null);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _push = ref.read(pushServiceProvider)
      ..activeConversationId = widget.conversationId
      ..clearConversation(widget.conversationId);
    _markRead();
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
    if (_push.activeConversationId == widget.conversationId) {
      _push.activeConversationId = null;
    }
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

    // Пока экран открыт, входящие сразу считаются прочитанными.
    ref.listen(messagesProvider(widget.conversationId), (previous, next) {
      final before = previous?.value?.length ?? 0;
      if ((next.value?.length ?? 0) > before && before > 0) {
        _markRead();
        // Отложенное могло как раз уйти — список «запланировано» устарел.
        ref.invalidate(scheduledMessagesProvider(widget.conversationId));
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          onTap: info == null || isDirect
              ? null
              : () => context.push(
                  '${Routes.chats}/${widget.conversationId}/info',
                ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                info?.displayName ?? widget.peerName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (info != null && !isDirect)
                Text(
                  membersLabel(info.memberCount),
                  style: TextStyle(fontSize: 12, color: AppColors.textDim),
                ),
            ],
          ),
        ),
        titleTextStyle: Theme.of(context).textTheme.titleLarge,
        actions: [
          IconButton(
            onPressed: () => showChatNotifySheet(
              context,
              widget.conversationId,
              info?.displayName ?? widget.peerName,
            ),
            tooltip: 'Уведомления',
            icon: Icon(switch (chatNotifyOf(ref, widget.conversationId)) {
              final n when n.isMuted => Icons.notifications_off_outlined,
              final n when n.mode == NotifyMode.vibrate => Icons.vibration,
              final n when n.mode == NotifyMode.silent => Icons.notifications_none,
              _ => Icons.notifications_active_outlined,
            }),
          ),
          if (info != null && isDirect)
            IconButton(
              onPressed: _showSecurityCode,
              tooltip: 'Код безопасности',
              icon: const Icon(Icons.verified_user_outlined),
            )
          else if (info != null)
            IconButton(
              onPressed: () => context.push(
                '${Routes.chats}/${widget.conversationId}/info',
              ),
              tooltip: 'О группе',
              icon: const Icon(Icons.info_outline),
            ),
        ],
      ),
      body: Column(
        children: [
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
                final items = hidden.isEmpty
                    ? all
                    : [
                        for (final m in all)
                          if (!hidden.contains(m.id)) m,
                      ];
                if (items.isEmpty) {
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
                final list = ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.gutter,
                    14,
                    AppSpacing.gutter,
                    14,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final message = items[items.length - 1 - index];
                    final mine = message.senderId == myId;
                    return Semantics(
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
                          child: MessageBubble(
                            message: message,
                            mine: mine,
                            showSender: !isDirect && !mine,
                            onMediaMore: (viewerContext) =>
                                _openMenu(viewerContext, message, myId),
                          ),
                        ),
                        ),
                      ),
                    );
                  },
                );
                return list;
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
    );
  }

  Future<void> _showSecurityCode() async {
    final code = ref
        .read(chatRepositoryProvider)
        .securityCode(widget.conversationId);
    await showModalBottomSheet<void>(
      context: context,
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
