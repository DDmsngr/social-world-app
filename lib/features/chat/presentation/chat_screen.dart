import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/debug/app_log.dart';
import '../../../core/errors/friendly_error.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/sw_widgets.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../domain/entities/chat_message.dart';
import 'conversations_screen.dart';
import 'providers/chat_providers.dart';
import 'widgets/message_bubble.dart';

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

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _controller = TextEditingController();
  bool _sending = false;
  String? _sendError;

  @override
  void initState() {
    super.initState();
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
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() {
      _sending = true;
      _sendError = null;
    });
    try {
      await ref
          .read(chatRepositoryProvider)
          .send(conversationId: widget.conversationId, text: text);
      _controller.clear();
      // Новый личный диалог появляется в списке только после первого
      // сообщения.
      ref.invalidate(conversationsProvider);
    } catch (error) {
      AppLog.add('Сообщение не ушло: $error');
      if (mounted) {
        setState(() {
          _sendError = friendlyError(
            error,
            fallback: 'Не удалось отправить сообщение',
          );
        });
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(messagesProvider(widget.conversationId));
    final conversation = ref.watch(conversationProvider(widget.conversationId));
    final info = conversation.value;
    final myId = ref.watch(currentUserProvider)?.id ?? 'local-user';
    final isDirect = info?.isDirect ?? true;

    // Пока экран открыт, входящие сразу считаются прочитанными.
    ref.listen(messagesProvider(widget.conversationId), (previous, next) {
      final before = previous?.value?.length ?? 0;
      if ((next.value?.length ?? 0) > before && before > 0) _markRead();
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
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => _ErrorView(
                keysMissing: error.toString().contains('ключи'),
                onRetry: () =>
                    ref.invalidate(messagesProvider(widget.conversationId)),
              ),
              data: (items) {
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
                return ListView.builder(
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
                    return MessageBubble(
                      message: message,
                      mine: mine,
                      showSender: !isDirect && !mine,
                    );
                  },
                );
              },
            ),
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
          else
            _Composer(
              controller: _controller,
              onChanged: (_) => setState(() {}),
              error: _sendError,
              onSend: _controller.text.trim().isEmpty || _sending
                  ? null
                  : _send,
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
                  ? 'Собеседник ещё не заходил в приложение с включёнными '
                        'чатами. Как только он обновится и откроет приложение, '
                        'здесь можно будет переписываться.'
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

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.onChanged,
    required this.error,
    required this.onSend,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String? error;
  final VoidCallback? onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.hair)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (error != null) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  error!,
                  style: TextStyle(color: AppColors.danger, fontSize: 12),
                ),
              ),
              const SizedBox(height: 6),
            ],
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    onChanged: onChanged,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 4000,
                    buildCounter:
                        (
                          _, {
                          required currentLength,
                          required isFocused,
                          maxLength,
                        }) => null,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: 'Написать сообщение',
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: onSend,
                  tooltip: 'Отправить',
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.onPrimary,
                    disabledBackgroundColor: AppColors.card,
                    disabledForegroundColor: AppColors.textFaint,
                    minimumSize: const Size(46, 46),
                  ),
                  icon: const Icon(Icons.send, size: 19),
                ),
              ],
            ),
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
