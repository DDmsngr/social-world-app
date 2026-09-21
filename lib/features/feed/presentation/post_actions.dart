import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/debug/app_log.dart';
import '../../../core/errors/friendly_error.dart';
import '../../../core/links/deep_links.dart';
import '../../../core/permissions/content_permissions.dart';
import '../../../core/router/app_router.dart';
import '../../../core/share/share_service.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../moderation/domain/entities/report_reason.dart';
import '../../moderation/presentation/widgets/report_sheet.dart';
import '../../profile/domain/profile_models.dart';
import '../../profile/presentation/providers/profile_providers.dart';
import '../../saved/saved.dart';
import '../domain/entities/post.dart';
import '../domain/entities/publish_settings.dart';
import 'providers/feed_providers.dart';
import 'widgets/publish_settings_panel.dart';

/// Кто и что может делать с постом. Единственная точка, откуда экраны берут
/// права: своё — управление, чужое — жалоба, скрытие, блокировка.
ContentPermissions postPermissions(WidgetRef ref, Post post) => ContentPermissions(
  viewerId: ref.read(currentUserProvider)?.id,
  ownerId: post.authorId,
);

void _toast(BuildContext context, String text) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

/// Заголовок для шаринга и сохранённого: у статьи он свой, у момента — начало
/// текста.
String postTitle(Post post) {
  final title = post.title;
  if (title != null && title.isNotEmpty) return title;
  final body = post.body?.trim() ?? '';
  if (body.isEmpty) return 'Публикация ${post.authorName}';
  return body.length > 80 ? '${body.substring(0, 80)}…' : body;
}

Future<void> sharePost(BuildContext context, Post post) => ShareService.share(
  context,
  target: post.isRoute ? LinkTarget.route : LinkTarget.post,
  id: post.isRoute ? post.routeId! : post.id,
  title: postTitle(post),
  details: post.placeTitle,
);

Future<void> toggleSavePost(BuildContext context, WidgetRef ref, Post post) async {
  final result = await ref
      .read(savedProvider.notifier)
      .toggle(
        SavedKind.post,
        post.id,
        title: postTitle(post),
        subtitle: post.authorName,
      );
  if (!context.mounted) return;
  _toast(
    context,
    switch (result) {
      true => 'Добавлено в «Сохранённое»',
      false => 'Убрано из «Сохранённого»',
      null => 'Не удалось сохранить — нет связи',
    },
  );
}

/// Жалоба на чужой пост. Для своего до листа дело не доходит: права
/// проверяются здесь, в репозитории и в базе.
Future<void> reportPost(BuildContext context, WidgetRef ref, Post post) async {
  final permissions = postPermissions(ref, post);
  if (!permissions.canReport) {
    _toast(context, 'На свою публикацию пожаловаться нельзя');
    return;
  }

  final sent = await showReportSheet(
    context,
    target: ReportTarget.post,
    targetId: post.id,
    authorId: post.authorId,
    subject: '${post.authorName}: ${postTitle(post)}',
  );
  if (!sent || !context.mounted) return;
  ref.read(feedProvider.notifier).hide(post.id);
  _toast(context, 'Жалоба отправлена. Этот пост вам больше не покажем');
}

Future<void> editPost(BuildContext context, WidgetRef ref, Post post) async {
  try {
    postPermissions(ref, post).requireOwner();
  } on PermissionDeniedException catch (error) {
    _toast(context, error.message);
    return;
  }
  await context.push('${Routes.posts}/${post.id}/edit', extra: post);
}

/// Быстрая смена «кому виден» и «показывать место» без открытия редактора.
Future<void> changePostSettings(
  BuildContext context,
  WidgetRef ref,
  Post post,
) async {
  try {
    postPermissions(ref, post).requireOwner();
  } on PermissionDeniedException catch (error) {
    _toast(context, error.message);
    return;
  }

  final chosen = await showModalBottomSheet<PublishSettings>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => PublishSettingsSheet(
      initial: PublishSettings(
        visibility: post.visibility,
        showGeo: post.showGeo,
      ),
    ),
  );
  if (chosen == null || !context.mounted) return;

  try {
    final updated = await ref.read(feedRepositoryProvider).updatePost(
      post,
      body: post.body ?? '',
      title: post.title,
      settings: chosen,
      keepMediaUrls: post.mediaUrls,
      placeId: post.placeId,
      placeTitle: post.placeTitle,
      placeLatitude: post.placeLatitude,
      placeLongitude: post.placeLongitude,
    );
    ref.read(feedProvider.notifier).replacePost(updated);
    ref.invalidate(userPostsProvider(post.authorId));
    if (context.mounted) _toast(context, 'Настройки публикации сохранены');
  } catch (error) {
    AppLog.add('Настройки поста не сохранились: $error');
    if (!context.mounted) return;
    _toast(context, friendlyError(error, fallback: 'Не удалось сохранить'));
  }
}

Future<void> deleteOwnPost(BuildContext context, WidgetRef ref, Post post) async {
  try {
    postPermissions(ref, post).requireOwner();
  } on PermissionDeniedException catch (error) {
    _toast(context, error.message);
    return;
  }

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Удалить публикацию?'),
      content: const Text('Её не получится вернуть.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Отмена'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Удалить'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  try {
    await ref.read(feedRepositoryProvider).deletePost(post.id);
    ref.read(feedProvider.notifier).remove(post.id);
    ref.invalidate(userPostsProvider(post.authorId));
    if (context.mounted) _toast(context, 'Публикация удалена');
  } catch (error) {
    AppLog.add('Пост не удалился: $error');
    if (context.mounted) {
      _toast(context, friendlyError(error, fallback: 'Не удалось удалить'));
    }
  }
}

/// «Скрыть публикации автора» (mute) и «Заблокировать» (block) — одна
/// операция с разным видом; подтверждение только для блокировки.
Future<void> blockAuthor(
  BuildContext context,
  WidgetRef ref, {
  required String userId,
  required String name,
  String? avatarUrl,
  required BlockKind kind,
}) async {
  final viewer = ref.read(currentUserProvider)?.id;
  if (viewer == null || viewer == userId) return;

  if (kind == BlockKind.block) {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Заблокировать $name?'),
        content: const Text(
          'Вы не увидите публикации, события и присутствие этого человека, '
          'а он — ваши. Подписки между вами будут отменены. '
          'Разблокировать можно в настройках.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Заблокировать'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
  }

  try {
    await ref
        .read(blocksProvider.notifier)
        .block(userId, kind, displayName: name, avatarUrl: avatarUrl);
    if (!context.mounted) return;
    _toast(
      context,
      kind == BlockKind.block
          ? '$name заблокирован(а)'
          : 'Публикации $name скрыты',
    );
  } catch (error) {
    AppLog.add('Блокировка не сохранилась: $error');
    if (context.mounted) {
      _toast(context, friendlyError(error, fallback: 'Не удалось выполнить'));
    }
  }
}
