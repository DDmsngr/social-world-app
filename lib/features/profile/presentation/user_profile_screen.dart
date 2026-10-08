import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/feature_flags.dart';
import '../../../core/debug/app_log.dart';
import '../../../core/errors/friendly_error.dart';
import '../../../core/links/deep_links.dart';
import '../../../core/media/photo_viewer.dart';
import '../../../core/permissions/content_permissions.dart';
import '../../../core/router/app_router.dart';
import '../../../core/share/share_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/video_avatar.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/update/update_dot.dart';
import '../../../core/widgets/state_message.dart';
import '../../../core/widgets/sw_widgets.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../chat/presentation/providers/chat_providers.dart';
import '../../feed/presentation/post_actions.dart';
import '../../moderation/domain/entities/report_reason.dart';
import '../../moderation/presentation/widgets/report_sheet.dart';
import '../../../core/media/media_kind.dart';
import '../../feed/presentation/widgets/story_strip.dart';
import '../../notifications/notifications.dart';
import '../../stories/stories.dart';
import '../../stories/story_viewer.dart';
import '../domain/profile_models.dart';
import '../../feed/domain/entities/post.dart';
import 'providers/profile_providers.dart';
import 'widgets/profile_post_grid.dart';

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
        username: me.username,
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
          if (isMe) ...[
            Consumer(
              builder: (context, ref, _) {
                final unread = ref.watch(unreadNotificationsProvider);
                return IconButton(
                  onPressed: () => context.push(Routes.notifications),
                  tooltip: 'Уведомления',
                  icon: Badge(
                    isLabelVisible: unread > 0,
                    label: Text(unread > 99 ? '99+' : '$unread'),
                    backgroundColor: AppColors.primary,
                    child: const Icon(Icons.notifications_none),
                  ),
                );
              },
            ),
            IconButton(
              onPressed: () => context.push(Routes.profileMenu),
              tooltip: 'Мои разделы',
              icon: const Icon(Icons.menu),
            ),
            IconButton(
              onPressed: () => context.push(Routes.settings),
              tooltip: 'Настройки',
              icon: const UpdateDot(child: Icon(Icons.settings_outlined)),
            ),
          ] else if (profile != null) ...[
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

/// Что показывать в сетке профиля. Первый фильтр — «всё подряд», значком.
/// Вкладка есть, только если у человека есть такие публикации.
enum _PostFilter {
  all(Icons.grid_view_rounded, null),
  photo(Icons.image_outlined, 'Фото'),
  video(Icons.play_circle_outline, 'Видео'),
  article(Icons.article_outlined, 'Статьи'),
  route(Icons.route_outlined, 'Маршруты'),
  text(Icons.notes, 'Заметки'),
  stories(Icons.amp_stories_outlined, 'Истории');

  const _PostFilter(this.icon, this.label);
  final IconData icon;
  final String? label;

  bool matches(Post post) => switch (this) {
    all => true,
    photo => !post.isArticle && !post.isRoute && post.photoUrls.isNotEmpty,
    video => post.mediaUrls.any(isVideoUrl),
    article => post.isArticle,
    route => post.isRoute,
    text => !post.isArticle && !post.isRoute && !post.hasMedia,
    stories => false,
  };
}

class _Body extends ConsumerStatefulWidget {
  const _Body({required this.profile, required this.isMe});

  final UserProfile profile;
  final bool isMe;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  var _filter = _PostFilter.all;

  UserProfile get profile => widget.profile;
  bool get isMe => widget.isMe;

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

  Future<void> _openChat(BuildContext context, WidgetRef ref) async {
    try {
      final conversationId = await ref
          .read(chatRepositoryProvider)
          .openDirect(profile.id);
      if (context.mounted) {
        context.go(
          '${Routes.chats}/$conversationId',
          extra: profile.displayName,
        );
      }
    } catch (error) {
      AppLog.add('Диалог не открылся: $error');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              friendlyError(error, fallback: 'Не удалось открыть переписку'),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final blockKind = profile.blockKind;
    final storyGroup = (ref.watch(storiesProvider).value ?? const <StoryGroup>[])
        .where((g) => g.authorId == profile.id)
        .firstOrNull;

    final posts = blockKind == null ? ref.watch(userPostsProvider(profile.id)) : null;
    final postCount = posts?.value?.length;
    final bottom = 24 + MediaQuery.paddingOf(context).bottom;

    final header = <Widget>[
        Row(
          children: [
            GestureDetector(
              onTap: profile.avatarUrl == null
                  ? null
                  : () => showPhotoViewer(context, urls: [profile.avatarUrl!]),
              child: Features.videoAvatar && profile.avatarVideoUrl != null
                  ? VideoAvatar(
                      url: profile.avatarVideoUrl!,
                      radius: 38,
                      // Пока ролик грузится — обычное фото.
                      fallback: UserAvatar(
                        name: profile.displayName,
                        url: profile.avatarUrl,
                        radius: 38,
                      ),
                    )
                  : UserAvatar(
                      name: profile.displayName,
                      url: profile.avatarUrl,
                      radius: 38,
                    ),
            ),
            const SizedBox(width: 12),
            _Stat(value: postCount ?? 0, label: 'публикации'),
            _Stat(
              value: profile.followerCount,
              label: 'подписчики',
              onTap: () => context.push(
                '${Routes.user}/${profile.id}/followers',
              ),
            ),
            _Stat(
              value: profile.followingCount,
              label: 'подписки',
              onTap: () => context.push(
                '${Routes.user}/${profile.id}/following',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(profile.displayName, style: theme.textTheme.titleLarge),
        if (profile.username != null)
          Text(
            '@${profile.username}',
            style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.primaryTint),
          ),
        if (profile.city != null)
          Text(profile.city!, style: theme.textTheme.bodyMedium),
        if (profile.bio != null && profile.bio!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(profile.bio!, style: theme.textTheme.bodyLarge),
        ],
        const SizedBox(height: 4),
        if (isMe)
          // Свои баллы открываются: сколько и за что, плюс справка.
          InkWell(
            onTap: () => context.push(Routes.activityPoints),
            borderRadius: BorderRadius.circular(AppRadius.chip),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Activity Points: ${profile.socialScore}',
                    style: TextStyle(fontSize: 13, color: AppColors.primaryTint),
                  ),
                  Icon(Icons.chevron_right, size: 18, color: AppColors.primaryTint),
                ],
              ),
            ),
          )
        else
          Text(
            'Activity Points: ${profile.socialScore}',
            style: TextStyle(fontSize: 12, color: AppColors.textDim),
          ),
        const SizedBox(height: 14),
        // Правка своего профиля — в настройках (шестерёнка сверху).
        if (isMe)
          const SizedBox.shrink()
        else if (blockKind != null)
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
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () => _toggleFollow(context, ref),
                  style: profile.followedByMe
                      ? FilledButton.styleFrom(
                          backgroundColor: AppColors.card,
                          foregroundColor: AppColors.primaryTint,
                        )
                      : null,
                  child: Text(
                    profile.followedByMe ? 'Вы подписаны' : 'Подписаться',
                  ),
                ),
              ),
              if (Features.chat) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _openChat(context, ref),
                    icon: const Icon(Icons.chat_bubble_outline, size: 18),
                    label: const Text('Написать'),
                  ),
                ),
              ],
            ],
          ),
        const SizedBox(height: 18),
    ];

    Widget message(Widget child) => SliverPadding(
      padding: EdgeInsets.fromLTRB(AppSpacing.gutter, 12, AppSpacing.gutter, bottom),
      sliver: SliverToBoxAdapter(child: child),
    );

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(userProfileProvider(profile.id));
        if (blockKind == null) {
          await ref.refresh(userPostsProvider(profile.id).future).catchError((_) => <Post>[]);
        }
      },
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 16, AppSpacing.gutter, 0),
            sliver: SliverList(delegate: SliverChildListDelegate(header)),
          ),
          if (posts != null) ...[
            SliverToBoxAdapter(child: Divider(height: 1, color: AppColors.hair)),
            const SliverToBoxAdapter(child: SizedBox(height: 2)),
            ...posts.when(
              loading: () => [
                message(const Center(child: CircularProgressIndicator())),
              ],
              error: (_, _) => [
                message(
                  Row(
                    children: [
                      const Expanded(child: Text('Не удалось загрузить публикации')),
                      TextButton(
                        onPressed: () => ref.invalidate(userPostsProvider(profile.id)),
                        child: const Text('Повторить'),
                      ),
                    ],
                  ),
                ),
              ],
              data: (items) {
                if (items.isEmpty && storyGroup == null) {
                  return [
                    message(
                      Text(
                        isMe
                            ? 'Вы ещё ничего не опубликовали. Начните со вкладки «Создать».'
                            : 'Публикаций пока нет.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ];
                }
                // В своём профиле плашка всегда целиком — все виды публикаций,
                // даже пустые: так видно, что вообще можно выложить. У чужого
                // — только те, что у человека есть.
                final available = [
                  for (final f in _PostFilter.values)
                    if (isMe ||
                        f == _PostFilter.all ||
                        (f == _PostFilter.stories ? storyGroup != null : items.any(f.matches)))
                      f,
                ];
                final filter = available.contains(_filter) ? _filter : _PostFilter.all;
                final shown = [for (final p in items) if (filter.matches(p)) p];
                final emptyStories = filter == _PostFilter.stories && storyGroup == null;
                return [
                  if (isMe || available.length > 2)
                    SliverToBoxAdapter(
                      child: _FilterBar(
                        filters: available,
                        selected: filter,
                        onSelected: (f) => setState(() => _filter = f),
                      ),
                    ),
                  if (emptyStories || (filter != _PostFilter.stories && shown.isEmpty))
                    message(
                      Text(
                        '${filter.label ?? 'Публикаций'}: пока нет.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    )
                  else if (filter == _PostFilter.stories)
                    _StoriesGrid(group: storyGroup!)
                  else
                    ProfilePostGrid(posts: shown),
                  SliverToBoxAdapter(child: SizedBox(height: bottom)),
                ];
              },
            ),
          ] else
            SliverToBoxAdapter(child: SizedBox(height: bottom)),
        ],
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.filters,
    required this.selected,
    required this.onSelected,
  });

  final List<_PostFilter> filters;
  final _PostFilter selected;
  final ValueChanged<_PostFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    // Одна плашка, как нижняя панель: только значки, выбранный подсвечен.
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 10, AppSpacing.gutter, 10),
      child: Container(
        height: 46,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: AppColors.hair),
        ),
        child: Row(
          children: [
            for (final f in filters)
              Expanded(
                child: Semantics(
                  button: true,
                  selected: f == selected,
                  label: f.label ?? 'Всё подряд',
                  child: Tooltip(
                    message: f.label ?? 'Всё подряд',
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onSelected(f),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        decoration: BoxDecoration(
                          color: f == selected ? AppColors.primary : Colors.transparent,
                          borderRadius: BorderRadius.circular(22),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          f.icon,
                          size: 22,
                          color: f == selected ? AppColors.onPrimary : AppColors.textDim,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Живые истории человека плитками; нажатие открывает просмотр с этой.
class _StoriesGrid extends StatelessWidget {
  const _StoriesGrid({required this.group});

  final StoryGroup group;

  @override
  Widget build(BuildContext context) {
    return SliverGrid(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
        childAspectRatio: 9 / 16,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, i) => GestureDetector(
          onTap: () => showStories(
            context,
            groups: [group.copyWith(stories: group.stories.sublist(i))],
            initialGroup: 0,
          ),
          child: StoryCover(story: group.stories[i]),
        ),
        childCount: group.stories.length,
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.onTap});

  final int value;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              Text('$value', style: AppTypography.serif(24)),
              const SizedBox(height: 2),
              // При крупном системном шрифте подпись ужимается, а не рвётся
              // посреди слова («публикаци/и»).
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(fontSize: 12, color: AppColors.textDim),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

