import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/state_message.dart';
import '../../../core/widgets/user_avatar.dart';
import '../domain/profile_models.dart';
import 'providers/profile_providers.dart';

/// Список заблокированных и скрытых: отсюда ограничение снимается.
class BlockedUsersScreen extends ConsumerWidget {
  const BlockedUsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blocks = ref.watch(blocksProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Заблокированные'),
        leading: IconButton(
          onPressed: () =>
              context.canPop() ? context.pop() : context.go(Routes.settings),
          tooltip: 'Назад',
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: blocks.when(
        loading: () => const LoadingView(),
        error: (_, _) => StateMessage.error(
          onAction: () => ref.invalidate(blocksProvider),
        ),
        data: (map) {
          if (map.isEmpty) {
            return const StateMessage(
              title: 'Список пуст',
              text: 'Здесь появятся люди, которых вы заблокировали или '
                  'чьи публикации скрыли.',
              icon: Icons.block_outlined,
            );
          }
          final items = map.values.toList();
          return ListView.separated(
            padding: AppSpacing.page(context),
            itemCount: items.length,
            separatorBuilder: (_, _) => const Divider(),
            itemBuilder: (context, index) {
              final item = items[index];
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: UserAvatar(
                  name: item.displayName,
                  url: item.avatarUrl,
                  userId: item.userId,
                ),
                title: Text(item.displayName),
                subtitle: Text(
                  item.kind == BlockKind.block ? 'Заблокирован' : 'Публикации скрыты',
                ),
                trailing: TextButton(
                  onPressed: () async {
                    try {
                      await ref.read(blocksProvider.notifier).unblock(item.userId);
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Не удалось снять ограничение')),
                        );
                      }
                    }
                  },
                  child: const Text('Снять'),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
