import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/debug/app_log.dart';
import '../../../../core/errors/friendly_error.dart';
import '../../../../core/links/deep_links.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../chat/domain/entities/chat_message.dart';
import '../../../chat/presentation/providers/chat_providers.dart';
import '../../../chat/presentation/widgets/forward_picker.dart';
import '../../../profile/presentation/providers/profile_providers.dart';
import '../../domain/entities/post.dart';
import '../post_actions.dart';
import '../providers/feed_providers.dart';

/// Репост — обычный пост, весь текст которого ссылка на другой пост. Карточка
/// узнаёт это и показывает оригинал внутри. Возвращает id оригинала.
String? repostOf(Post post) {
  final body = post.body?.trim() ?? '';
  if (body.isEmpty || body.contains(RegExp(r'\s'))) return null;
  final uri = Uri.tryParse(body);
  if (uri == null) return null;
  final link = DeepLinks.parse(uri);
  return link?.target == LinkTarget.post ? link!.id : null;
}

/// Ссылка на пост; у репоста — на оригинал, чтобы цепочки не росли.
Uri _linkFor(Post post) {
  if (post.isRoute) return DeepLinks.shareUri(LinkTarget.route, post.routeId!);
  return DeepLinks.shareUri(LinkTarget.post, repostOf(post) ?? post.id);
}

enum _ShareTo { profile, chats, outside }

/// «Поделиться» под постом: сначала — внутри приложения (себе в профиль, в
/// личку, группу или канал), ссылкой наружу — последним пунктом.
Future<void> showPostShare(BuildContext context, WidgetRef ref, Post post) async {
  final choice = await showModalBottomSheet<_ShareTo>(
    context: context,
    useRootNavigator: true,
    backgroundColor: AppColors.ink2,
    showDragHandle: true,
    builder: (context) => SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!post.isRoute)
            ListTile(
              leading: Icon(Icons.repeat, color: AppColors.primaryTint),
              title: const Text('В свой профиль'),
              subtitle: const Text('Репост появится у вас в ленте и в профиле'),
              onTap: () => Navigator.of(context).pop(_ShareTo.profile),
            ),
          ListTile(
            leading: Icon(Icons.send_outlined, color: AppColors.primaryTint),
            title: const Text('В чат, группу или канал'),
            onTap: () => Navigator.of(context).pop(_ShareTo.chats),
          ),
          ListTile(
            leading: Icon(Icons.ios_share, color: AppColors.textDim),
            title: const Text('Ссылкой в другое приложение'),
            onTap: () => Navigator.of(context).pop(_ShareTo.outside),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;

  switch (choice) {
    case _ShareTo.profile:
      await _repost(context, ref, post);
    case _ShareTo.chats:
      await _toChats(context, ref, post);
    case _ShareTo.outside:
      await sharePost(context, post);
  }
}

Future<void> _repost(BuildContext context, WidgetRef ref, Post post) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final created = await ref.read(feedRepositoryProvider).createPost(
      body: _linkFor(post).toString(),
    );
    ref.read(feedProvider.notifier).prepend(created);
    ref.invalidate(myPostsProvider);
    final me = ref.read(currentUserProvider)?.id;
    if (me != null) ref.invalidate(userPostsProvider(me));
    messenger.showSnackBar(const SnackBar(content: Text('Репост в вашем профиле')));
  } catch (error) {
    AppLog.add('Репост не удался: $error');
    messenger.showSnackBar(
      SnackBar(content: Text(friendlyError(error, fallback: 'Не удалось сделать репост'))),
    );
  }
}

Future<void> _toChats(BuildContext context, WidgetRef ref, Post post) async {
  final me = ref.read(currentUserProvider)?.id ?? '';
  final message = ChatMessage(
    id: 'share-${post.id}',
    conversationId: '',
    senderId: me,
    sentAt: DateTime.now(),
    text: '${postTitle(post)}\n${_linkFor(post)}',
  );
  final messenger = ScaffoldMessenger.of(context);
  final result = await showForwardPicker(
    context,
    messages: [message],
    authorOf: (_) => '',
    withAuthor: false,
    title: 'Поделиться',
  );
  if (result == null) return;
  final all = ref.read(conversationsProvider).value ?? const [];
  messenger.showSnackBar(SnackBar(content: Text(forwardSummary(result, all))));
}
