import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/debug/app_log.dart';
import '../../../core/errors/friendly_error.dart';
import '../../../core/links/deep_links.dart';
import '../../../core/media/photo_viewer.dart';
import '../../../core/permissions/content_permissions.dart';
import '../../../core/router/app_router.dart';
import '../../../core/share/share_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/update/update_dot.dart';
import '../../../core/widgets/state_message.dart';
import '../../../core/widgets/sw_widgets.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../feed/presentation/post_actions.dart';
import '../../feed/presentation/widgets/post_card.dart';
import '../../moderation/domain/entities/report_reason.dart';
import '../../moderation/presentation/widgets/report_sheet.dart';
import '../../notifications/notifications.dart';
import '../domain/profile_models.dart';
import 'providers/profile_providers.dart';

/// Профиль человека — свой и чужой одним экраном на общей модели
/// [UserProfile]. Что можно делать, решает [ContentPermissions]: у своего
/// профиля — правка и разделы («Сохранённое», уведомления, настройки), у
/// чужого — подписка, жалоба, скрытие и блокировка. Править чужой профиль
/// экран не даёт ни при каких условиях, а сервер не даёт этого и в обход.
class UserProfileScreen extends ConsumerWidget {
  const UserProfileScreen({
    super.key,
    required this.userId,

    /// true — вкладка «Профиль» в нижней навигации: без кнопки «назад».
    this.embedded = false,
  });

  final String userId;
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserProvider);
    final permissions = ContentPermissions(viewerId: me?.id, ownerId: userId);
    final isMe = permissions.isOwner;
    final card = ref.watch(userProfileProvider(userId));

    // Своя анкета всегда берётся из сессии: после правки она обновляется
    // мгновенно, не дожидаясь повторного запроса карточки.
    UserProfile? profile = card.value;
    if (isMe && me != null) {
      profile = UserProfile(
        id: me.id,
        displayName: me.displayName ?? 'Без имени',
        avatarUrl: me.avatarUrl,
        bio: me.bio,
        city: me.city,
        socialScore: me.socialScore,
        followerCount: profile?.followerCount ?? 0,
        followingCount: profile?.followingCount ?? 0,
      );
    }

    Widget body;
    if (profile != null) {
      body = _Body(profile: profile, isMe: isMe);
    } else if (card.isLoading) {
      body = const LoadingView();
    } else if (card.hasError) {
      body = StateMessage.error(
        title: 'Профиль не загрузился',
        onAction: () => ref.invalidate(userProfileProvider(userId)),
      );
    } else {
      body = const StateMessage(
        title: 'Профиль недоступен',
        text: 'Человек мог удалить аккаунт или ограничить доступ.',
        icon: Icons.person_off_outlined,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(isMe ? 'Профиль' : (profile?.displayName ?? 'Профиль')),
        leading: embedded
            ? null
            : IconButton(
                onPressed: () =>
                    context.canPop() ? context.pop() : context.go(Routes.home),
                tooltip: 'Назад',
                icon: const Icon(Icons.arrow_back),
              ),
        automaticallyImplyLeading: false,
        actions: [
          if (isMe)
            IconButton(
              onPressed: () => context.push(Routes.settings),
              tooltip: 'Настройки',
              icon: const UpdateDot(child: Icon(Icons.settings_outlined)),
            )
          else if (profile != null) ...[
            Builder(
              builder: (context) => IconButton(
                onPressed: () => ShareService.share(
                  context,
                  target: LinkTarget.profile,
                  id: profile!.id,
                  title: profile.displayName,
                  details: profile.city,
                ),
                tooltip: 'Поделиться',
                icon: const Icon(Icons.ios_share),
              ),
            ),
            _OtherMenu(profile: profile),
          ],
        ],
      ),
      body: body,
    );
  }
}

class _OtherMenu extends ConsumerWidget {
  const _OtherMenu({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blocked = profile.blockKind != null;

    return PopupMenuButton<String>(
      tooltip: 'Действия',
      color: AppColors.ink2,
      onSelected: (value) async {
        switch (value) {
          case 'report':
            final sent = await showReportSheet(
              context,
              target: ReportTarget.profile,
              targetId: profile.id,
              authorId: profile.id,
              subject: profile.displayName,
            );
            if (sent && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Жалоба отправлена')),
              );
            }
          case 'mute' || 'block':
            await blockAuthor(
              context,
              ref,
              userId: profile.id,
              name: profile.displayName,
              avatarUrl: profile.avatarUrl,
              kind: value == 'block' ? BlockKind.block : BlockKind.mute,
            );
          case 'unblock':
            try {
              await ref.read(blocksProvider.notifier).unblock(profile.id);
            } catch (error) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      friendlyError(error, fallback: 'Не удалось выполнить'),
                    ),
                  ),
                );
              }
            }
        }
      },
      itemBuilder: (_) => [
        if (blocked)
          const PopupMenuItem(
            value: 'unblock',
            child: Text('Снять ограничение'),
          )
        else ...const [
          PopupMenuItem(value: 'mute', child: Text('Скрыть публикации')),
          PopupMenuItem(value: 'block', child: Text('Заблокировать')),
        ],
        const PopupMenuItem(value: 'report', child: Text('Пожаловаться')),
      ],
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.profile, required this.isMe});

  final UserProfile profile;
  final bool isMe;

  Future<void> _toggleFollow(BuildContext context, WidgetRef ref) async {
    final follow = !profile.followedByMe;
    try {
      await ref
          .read(profileRepositoryProvider)
          .setFollow(profile.id, follow: follow);
      ref.invalidate(userProfileProvider(profile.id));
    } catch (error) {
      AppLog.add('Подписка не сохранилась: $error');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              friendlyError(error, fallback: 'Не удалось выполнить'),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final blockKind = profile.blockKind;

    return ListView(
      padding: AppSpacing.page(context, top: 16),
      children: [
        Row(
          children: [
            GestureDetector(
              onTap: profile.avatarUrl == null
                  ? null
                  : () => showPhotoViewer(context, urls: [profile.avatarUrl!]),
              child: UserAvatar(
                name: profile.displayName,
                url: profile.avatarUrl,
                radius: 38,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(profile.displayName, style: AppTypography.serif(28)),
                  if (profile.city != null) ...[
                    const SizedBox(height: 2),
                    Text(profile.city!, style: theme.textTheme.bodyMedium),
                  ],
                ],
              ),
            ),
          ],
        ),
        if (profile.bio != null && profile.bio!.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(profile.bio!, style: theme.textTheme.bodyLarge),
        ],
        const SizedBox(height: 18),
        Row(
          children: [
            _Stat(value: profile.followerCount, label: 'подписчиков'),
            _Stat(value: profile.followingCount, label: 'подписок'),
            _Stat(value: profile.socialScore, label: 'Social Score'),
          ],
        ),
        const SizedBox(height: 18),
        if (isMe) ...[
          OutlinedButton.icon(
            onPressed: () => context.push(Routes.editProfile),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Редактировать профиль'),
          ),
          const SizedBox(height: 14),
          _MenuTile(
            icon: Icons.bookmark_border,
            title: 'Сохранённое',
            onTap: () => context.push(Routes.saved),
          ),
          Consumer(
            builder: (context, ref, _) {
              final unread = ref.watch(unreadNotificationsProvider);
              return _MenuTile(
                icon: Icons.notifications_none,
                title: 'Уведомления',
                trailing: unread == 0 ? null : '$unread новых',
                onTap: () => context.push(Routes.notifications),
              );
            },
          ),
        ] else if (blockKind != null)
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  blockKind == BlockKind.block
                      ? 'Вы заблокировали этого человека'
                      : 'Вы скрыли публикации этого человека',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  'Его публикации и события вам не показываются.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () =>
                      ref.read(blocksProvider.notifier).unblock(profile.id),
                  child: const Text('Снять ограничение'),
                ),
              ],
            ),
          )
        else
          FilledButton(
            onPressed: () => _toggleFollow(context, ref),
            style: profile.followedByMe
                ? FilledButton.styleFrom(
                    backgroundColor: AppColors.card,
                    foregroundColor: AppColors.primaryTint,
                  )
                : null,
            child: Text(profile.followedByMe ? 'Вы подписаны' : 'Подписаться'),
          ),
        const SizedBox(height: 26),
        if (blockKind == null) _Posts(userId: profile.id, isMe: isMe),
      ],
    );
  }
}

class _Posts extends ConsumerWidget {
  const _Posts({required this.userId, required this.isMe});

  final String userId;
  final bool isMe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posts = ref.watch(userPostsProvider(userId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('Публикации'),
        const SizedBox(height: 12),
        posts.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, _) => Row(
            children: [
              const Expanded(child: Text('Не удалось загрузить публикации')),
              TextButton(
                onPressed: () => ref.invalidate(userPostsProvider(userId)),
                child: const Text('Повторить'),
              ),
            ],
          ),
          data: (items) => items.isEmpty
              ? Text(
                  isMe
                      ? 'Вы ещё ничего не опубликовали. Начните со вкладки «Создать».'
                      : 'Публикаций пока нет.',
                  style: Theme.of(context).textTheme.bodyMedium,
                )
              : Column(
                  children: [for (final post in items) PostCard(post: post)],
                ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text('$value', style: AppTypography.serif(24)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 12, color: AppColors.textDim)),
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        onTap: onTap,
        child: Row(
          children: [
            Icon(icon, color: AppColors.primaryTint),
            const SizedBox(width: 14),
            Expanded(child: Text(title)),
            if (trailing != null)
              Text(
                trailing!,
                style: TextStyle(color: AppColors.primaryTint, fontSize: 13),
              ),
            Icon(Icons.chevron_right, color: AppColors.textFaint),
          ],
        ),
      ),
    );
  }
}
