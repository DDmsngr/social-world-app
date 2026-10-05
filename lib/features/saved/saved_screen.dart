import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/links/deep_links.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/state_message.dart';
import '../../core/widgets/sw_widgets.dart';
import '../chat/domain/entities/conversation.dart';
import '../chat/presentation/providers/chat_pins_providers.dart';
import '../chat/presentation/providers/chat_providers.dart';
import 'saved.dart';

/// Профиль → Сохранённое. Две вкладки: «Публикации» — посты, события, места и
/// маршруты, которые человек отложил, и «Сообщения» — закладки на сообщения из
/// чатов. Состояние лежит на сервере, поэтому переживает перезапуск.
class SavedScreen extends ConsumerWidget {
  const SavedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Сохранённое'),
          leading: IconButton(
            onPressed: () =>
                context.canPop() ? context.pop() : context.go(Routes.profile),
            tooltip: 'Назад',
            icon: const Icon(Icons.arrow_back),
          ),
          bottom: const TabBar(
            tabs: [Tab(text: 'Публикации'), Tab(text: 'Сообщения')],
          ),
        ),
        body: const TabBarView(children: [_SavedPosts(), _SavedMessages()]),
      ),
    );
  }
}

class _SavedPosts extends ConsumerWidget {
  const _SavedPosts();

  IconData _icon(SavedKind kind) => switch (kind) {
    SavedKind.post => Icons.article_outlined,
    SavedKind.event => Icons.event_outlined,
    SavedKind.place => Icons.place_outlined,
    SavedKind.route => Icons.timeline,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(savedItemsProvider);

    return items.when(
      loading: () => const LoadingView(),
      error: (_, _) => StateMessage.error(
        onAction: () => ref.invalidate(savedItemsProvider),
      ),
      data: (list) {
        if (list.isEmpty) {
          return const StateMessage(
            title: 'Пока ничего нет',
            text: 'Сохраняйте посты, события, места и маршруты закладкой — '
                'они соберутся здесь.',
            icon: Icons.bookmark_border,
          );
        }
        return RefreshIndicator(
          onRefresh: () async => ref.refresh(savedItemsProvider.future),
          child: ListView.separated(
            padding: AppSpacing.page(context),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final item = list[index];
              return GlassCard(
                padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
                onTap: () => context.push(
                  DeepLinks.locationFor(item.kind.link, item.id),
                ),
                child: Row(
                  children: [
                    Icon(_icon(item.kind), color: AppColors.primaryTint),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Text(
                            [item.kind.label, ?item.subtitle].join(' · '),
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => ref
                          .read(savedProvider.notifier)
                          .toggle(item.kind, item.id),
                      tooltip: 'Убрать из сохранённого',
                      icon: Icon(Icons.bookmark, color: AppColors.primaryTint),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

/// Закладки на сообщения из чатов. Нажатие открывает чат на этом сообщении.
class _SavedMessages extends ConsumerWidget {
  const _SavedMessages();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(bookmarkedMessagesProvider(null));
    final conversations = ref.watch(conversationsProvider).value ?? const <Conversation>[];
    String nameOf(String id) =>
        conversations.where((c) => c.id == id).firstOrNull?.displayName ?? 'Чат';

    return items.when(
      loading: () => const LoadingView(),
      error: (_, _) => StateMessage.error(
        onAction: () => ref.invalidate(bookmarkedMessagesProvider(null)),
      ),
      data: (list) {
        if (list.isEmpty) {
          return const StateMessage(
            title: 'Закладок на сообщения нет',
            text: 'В переписке нажмите на сообщение и держите — в меню будет '
                '«Установить закладку».',
            icon: Icons.bookmark_add_outlined,
          );
        }
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(myBookmarksProvider);
            await ref.read(myBookmarksProvider.future);
          },
          child: ListView.separated(
            padding: AppSpacing.page(context),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final m = list[index].message;
              final chat = nameOf(m.conversationId);
              return GlassCard(
                padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
                onTap: () => context.push(
                  '${Routes.chats}/${m.conversationId}?m=${m.id}',
                  extra: chat,
                ),
                child: Row(
                  children: [
                    Icon(Icons.chat_bubble_outline, color: AppColors.primaryTint),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            m.preview,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Text(
                            chat,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => ref
                          .read(myBookmarksProvider.notifier)
                          .toggle(m.id, m.conversationId),
                      tooltip: 'Убрать закладку',
                      icon: Icon(Icons.bookmark, color: AppColors.primaryTint),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}
