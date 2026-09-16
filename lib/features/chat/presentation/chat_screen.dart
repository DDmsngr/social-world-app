import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
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
    if (text.isEmpty) return;

    _controller.clear();
    setState(() {});
    await ref
        .read(chatRepositoryProvider)
        .send(conversationId: widget.conversationId, text: text);

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
            onSend: _controller.text.trim().isEmpty ? null : _send,
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.onChanged,
    required this.onSend,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback? onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.hair)),
        ),
        child: Row(
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
      ),
    );
  }
}

/// Пока крипто не подключено, статус доставки — единственная честная метка.
String messageStatusLabel(MessageStatus status) => switch (status) {
  MessageStatus.sending => 'отправляется',
  MessageStatus.sent => 'отправлено',
  MessageStatus.delivered => 'доставлено',
  MessageStatus.read => 'прочитано',
  MessageStatus.failed => 'не ушло',
};
