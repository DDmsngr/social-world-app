import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/state_message.dart';
import '../../../core/widgets/sw_widgets.dart';
import '../../../core/widgets/user_avatar.dart';
import '../domain/entities/conversation.dart';
import 'providers/chat_providers.dart';

class ConversationsScreen extends ConsumerWidget {
  const ConversationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversations = ref.watch(conversationsProvider);
    final encryptionEnabled = ref
        .watch(chatRepositoryProvider)
        .endToEndEncryptionEnabled;

    return Scaffold(
      appBar: AppBar(title: const Text('Чаты')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('${Routes.chats}/new-group'),
        icon: const Icon(Icons.group_add_outlined),
        label: const Text('Группа'),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(conversationsProvider.future),
        child: conversations.when(
          loading: () => const LoadingView(),
          error: (_, _) => StateMessage.error(
            title: 'Не удалось загрузить чаты',
            onAction: () => ref.invalidate(conversationsProvider),
          ),
          data: (items) {
            if (items.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 80),
                  StateMessage(
                    title: 'Переписок пока нет',
                    text: 'Откройте профиль человека и нажмите «Написать» '
                        'или создайте группу.',
                    icon: Icons.forum_outlined,
                  ),
                ],
              );
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.gutter,
                12,
                AppSpacing.gutter,
                96,
              ),
              children: [
                if (!encryptionEnabled) ...[
                  const _EncryptionNotice(),
                  const SizedBox(height: 14),
                ],
                for (final conversation in items) ...[
                  _ConversationTile(conversation: conversation),
                  const SizedBox(height: 8),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({required this.conversation});

  final Conversation conversation;

  @override
  Widget build(BuildContext context) {
    final last = conversation.lastMessage;
    final preview = last == null
        ? 'Нет сообщений'
        : conversation.isDirect || last.senderName == null
        ? last.preview
        : '${last.senderName}: ${last.preview}';

    return GlassCard(
      padding: const EdgeInsets.all(14),
      onTap: () => context.push(
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
                conversation.kind == ConversationKind.quest
                    ? Icons.flag_outlined
                    : Icons.group_outlined,
                color: AppColors.primaryTint,
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
                Text(
                  preview,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (conversation.unreadCount > 0) ...[
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(AppRadius.chip),
              ),
              child: Text(
                '${conversation.unreadCount}',
                style: TextStyle(
                  fontSize: 12,
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
