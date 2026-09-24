import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/state_message.dart';
import '../../core/widgets/user_avatar.dart';
import 'notifications.dart';

/// Центр уведомлений. Каждое ведёт прямо на свой объект — тем же путём, что и
/// входящая ссылка. Push поверх этого списка (FCM) отдельный кусок
/// инфраструктуры: таблица уведомлений уже служит для него очередью.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    // Список мог устареть, пока экран был закрыт.
    Future.microtask(() => ref.read(notificationsProvider.notifier).refreshQuietly());
  }

  IconData _icon(NotificationKind kind) => switch (kind) {
    NotificationKind.follow => Icons.person_add_alt_outlined,
    NotificationKind.comment || NotificationKind.reply => Icons.mode_comment_outlined,
    NotificationKind.reaction => Icons.favorite_border,
    NotificationKind.eventJoin => Icons.group_add_outlined,
    NotificationKind.eventChanged => Icons.edit_calendar_outlined,
    NotificationKind.eventCancelled => Icons.event_busy_outlined,
    NotificationKind.message => Icons.forum_outlined,
    NotificationKind.questRequest || NotificationKind.questJoin => Icons.flag_outlined,
    NotificationKind.questApproved => Icons.check_circle_outline,
    NotificationKind.questRejected ||
    NotificationKind.questRemoved ||
    NotificationKind.questCancelled => Icons.flag_circle_outlined,
    NotificationKind.needResponse => Icons.volunteer_activism_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(notificationsProvider);
    final unread = ref.watch(unreadNotificationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Уведомления'),
        leading: IconButton(
          onPressed: () =>
              context.canPop() ? context.pop() : context.go(Routes.feed),
          tooltip: 'Назад',
          icon: const Icon(Icons.arrow_back),
        ),
        actions: [
          if (unread > 0)
            TextButton(
              onPressed: () => ref.read(notificationsProvider.notifier).markAllRead(),
              child: const Text('Прочитать все'),
            ),
        ],
      ),
      body: items.when(
        loading: () => const LoadingView(),
        error: (_, _) => StateMessage.error(
          onAction: () => ref.read(notificationsProvider.notifier).refresh(),
        ),
        data: (list) {
          if (list.isEmpty) {
            return const StateMessage(
              title: 'Пока тихо',
              text: 'Здесь появятся подписчики, комментарии, реакции и '
                  'новости о ваших событиях.',
              icon: Icons.notifications_none,
            );
          }
          return RefreshIndicator(
            onRefresh: () => ref.read(notificationsProvider.notifier).refresh(),
            child: ListView.separated(
              padding: EdgeInsets.only(
                top: 4,
                bottom: 24 + MediaQuery.paddingOf(context).bottom,
              ),
              itemCount: list.length,
              separatorBuilder: (_, _) => const Divider(),
              itemBuilder: (context, index) {
                final item = list[index];
                return ListTile(
                  tileColor: item.isUnread
                      ? AppColors.primary.withValues(alpha: 0.10)
                      : null,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.gutter,
                    vertical: 4,
                  ),
                  leading: item.actorName != null
                      ? UserAvatar(
                          name: item.actorName!,
                          url: item.actorAvatarUrl,
                        )
                      : CircleAvatar(
                          backgroundColor: AppColors.ink2,
                          child: Icon(_icon(item.kind), color: AppColors.primaryTint),
                        ),
                  title: Text(item.text, maxLines: 3, overflow: TextOverflow.ellipsis),
                  subtitle: Text(_when(item.createdAt)),
                  trailing: Icon(_icon(item.kind), size: 18, color: AppColors.textFaint),
                  onTap: () {
                    ref.read(notificationsProvider.notifier).markRead(item);
                    context.push(item.location);
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }
}

String _when(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'только что';
  if (diff.inMinutes < 60) return '${diff.inMinutes} мин назад';
  if (diff.inHours < 24) return '${diff.inHours} ч назад';
  if (diff.inDays == 1) return 'вчера';
  return '${diff.inDays} дн назад';
}
