import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/sw_widgets.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../domain/entities/chat_message.dart';
import 'providers/chat_providers.dart';
import 'widgets/message_bubble.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.peerName,
  });

  final String conversationId;
  final String peerName;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _sending = false;
  String? _sendError;

  @override
  void initState() {
    super.initState();
    ref
        .read(chatRepositoryProvider)
        .markRead(widget.conversationId)
        .then((_) => ref.invalidate(conversationsProvider));
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
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
    } catch (_) {
      if (mounted) {
        setState(() {
          _sendError = 'Не удалось отправить защищённое сообщение';
        });
      }
      return;
    } finally {
      if (mounted) setState(() => _sending = false);
    }

    if (!mounted || !_scrollController.hasClients) return;
    await _scrollController.animateTo(
      _scrollController.position.maxScrollExtent + 120,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(messagesProvider(widget.conversationId));
    final myId = ref.watch(currentUserProvider)?.id ?? 'local-user';

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.peerName),
        titleTextStyle: Theme.of(context).textTheme.titleLarge,
        actions: [
          IconButton(
            onPressed: _showSecurityCode,
            tooltip: 'Код безопасности',
            icon: const Icon(Icons.verified_user_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => Center(
                child: Text(
                  'Не удалось загрузить переписку',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              data: (items) => ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.gutter,
                  14,
                  AppSpacing.gutter,
                  14,
                ),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final message = items[index];
                  return MessageBubble(
                    message: message,
                    mine: message.senderId == myId,
                  );
                },
              ),
            ),
          ),
          _Composer(
            controller: _controller,
            onChanged: (_) => setState(() {}),
            error: _sendError,
            onSend: _controller.text.trim().isEmpty || _sending ? null : _send,
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
