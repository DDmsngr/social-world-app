import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/sw_widgets.dart';
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
      body: conversations.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: Text(
            'Не удалось загрузить чаты',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.gutter),
                child: Text(
                  'Переписок пока нет.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.gutter,
              12,
              AppSpacing.gutter,
              24,
            ),
            children: [
              if (!encryptionEnabled) ...[
                const _EncryptionNotice(),
                const SizedBox(height: 14),
              ],
              for (final conversation in items)
                GlassCard(
                  padding: const EdgeInsets.all(14),
                  onTap: () => context.push(
                    '${Routes.chats}/${conversation.id}',
                    extra: conversation.peerName,
                  ),
                  child: Row(
                    children: [
                      Stack(
                        children: [
                          CircleAvatar(
                            radius: 22,
                            backgroundColor: AppColors.ink,
                            child: Text(
                              conversation.peerName.characters.first
                                  .toUpperCase(),
                              style: AppTypography.serif(
                                18,
                                color: AppColors.primaryTint,
                              ),
                            ),
                          ),
                          if (conversation.online)
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppColors.success,
                                  border: Border.all(
                                    color: AppColors.card,
                                    width: 2,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              conversation.peerName,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              conversation.lastMessage?.text ?? 'Нет сообщений',
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
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
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
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Пока крипто не подключено, об этом сказано прямо. Мессенджер, который
/// выглядит защищённым, но не защищён, опаснее honest-заглушки.
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
