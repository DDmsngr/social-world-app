import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../providers/chat_pins_providers.dart';

/// Закладки этого чата. Возвращает id сообщения, к которому перейти, или null.
Future<String?> showChatBookmarks(BuildContext context, String conversationId) {
  return showModalBottomSheet<String>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: AppColors.ink2,
    showDragHandle: true,
    builder: (_) => _BookmarksSheet(conversationId: conversationId),
  );
}

class _BookmarksSheet extends ConsumerWidget {
  const _BookmarksSheet({required this.conversationId});

  final String conversationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(bookmarkedMessagesProvider(conversationId));
    final height = MediaQuery.sizeOf(context).height * 0.7;

    return SizedBox(
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 0, AppSpacing.gutter, 10),
            child: Text('Закладки', style: Theme.of(context).textTheme.titleLarge),
          ),
          Expanded(
            child: list.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => const Center(child: Text('Не удалось открыть закладки')),
              data: (items) {
                if (items.isEmpty) {
                  return Center(
                    child: Text(
                      'Закладок в этом чате нет',
                      style: TextStyle(color: AppColors.textDim),
                    ),
                  );
                }
                return ListView.separated(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.gutter,
                    0,
                    AppSpacing.gutter,
                    16 + MediaQuery.paddingOf(context).bottom,
                  ),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => Divider(height: 1, color: AppColors.hair),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final m = item.message;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        m.preview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        _when(m.sentAt),
                        style: TextStyle(color: AppColors.textDim, fontSize: 12),
                      ),
                      trailing: IconButton(
                        tooltip: 'Убрать закладку',
                        icon: Icon(Icons.bookmark_remove_outlined, color: AppColors.textDim),
                        onPressed: () => ref
                            .read(myBookmarksProvider.notifier)
                            .toggle(m.id, m.conversationId),
                      ),
                      onTap: () => Navigator.of(context).pop(m.id),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

String _when(DateTime time) {
  String two(int n) => n.toString().padLeft(2, '0');
  final t = time.toLocal();
  return '${two(t.day)}.${two(t.month)}.${t.year}, ${two(t.hour)}:${two(t.minute)}';
}
