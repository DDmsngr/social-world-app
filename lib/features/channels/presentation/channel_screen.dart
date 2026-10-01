import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/debug/app_log.dart';
import '../../../core/errors/friendly_error.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/state_message.dart';
import '../../chat/presentation/providers/chat_notify_providers.dart';
import '../../chat/presentation/providers/chat_providers.dart';
import '../../chat/presentation/widgets/chat_composer.dart';
import '../../chat/presentation/widgets/chat_notify_sheet.dart';
import '../data/channels_repository.dart';
import 'providers/channel_providers.dart';
import 'widgets/channel_post_card.dart';

/// Канал: лента постов снизу вверх, как в Telegram. Админы пишут обычным полем
/// ввода чата; читатель видит кнопку подписки или заявки.
class ChannelScreen extends ConsumerStatefulWidget {
  const ChannelScreen({super.key, required this.channelId, this.inviteToken});

  final String channelId;

  /// Пришёл по ссылке-приглашению в закрытый канал.
  final String? inviteToken;

  @override
  ConsumerState<ChannelScreen> createState() => _ChannelScreenState();
}

class _ChannelScreenState extends ConsumerState<ChannelScreen> {
  final _scroll = ScrollController();
  var _joining = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      // reverse: true — «конец» списка это верх экрана, там старые посты.
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 600) {
        ref.read(channelPostsProvider(widget.channelId).notifier).loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _markRead() async {
    try {
      await ref.read(channelsRepositoryProvider).markRead(widget.channelId);
      ref.invalidate(conversationsProvider);
    } catch (error) {
      AppLog.add('Канал не отметился прочитанным: $error');
    }
  }

  Future<void> _join() async {
    setState(() => _joining = true);
    try {
      final result = await ref
          .read(channelsRepositoryProvider)
          .join(widget.channelId, inviteToken: widget.inviteToken);
      ref.invalidate(channelInfoProvider(widget.channelId));
      ref.invalidate(channelPostsProvider(widget.channelId));
      ref.invalidate(conversationsProvider);
      ref.invalidate(chatNotifyProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result == JoinResult.joined
                ? 'Вы подписаны. Уведомления выключены — включить можно колокольчиком.'
                : 'Заявка отправлена. Админы канала её рассмотрят.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(error, fallback: 'Не удалось подписаться'))),
      );
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  Future<void> _deletePost(ChannelPost post) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Удалить пост?'),
        content: const Text('Пост и обсуждение под ним исчезнут у всех.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Удалить')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(chatRepositoryProvider).deleteForEveryone([post.message]);
      ref.read(channelPostsProvider(widget.channelId).notifier).remove(post.message.id);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(error, fallback: 'Не удалось удалить'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final infoAsync = ref.watch(channelInfoProvider(widget.channelId));
    final info = infoAsync.value;

    // Подписчик получает новые посты реалтаймом чатов: на каждое изменение
    // ленты подтягиваем верх и сбрасываем счётчик непрочитанного.
    if (info?.isMember ?? false) {
      ref.listen(messagesProvider(widget.channelId), (_, next) {
        if (next.hasValue) {
          ref.read(channelPostsProvider(widget.channelId).notifier).refreshTop();
          _markRead();
        }
      });
    }
    ref.listen(channelInfoProvider(widget.channelId), (_, next) {
      if (next.value?.isMember ?? false) _markRead();
    });

    final subtitle = info == null
        ? null
        : [
            if (!info.isPublic) 'закрытый канал',
            if (info.subscriberCount != null) _subscribers(info.subscriberCount!),
          ].join(' · ');

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => context.canPop() ? context.pop() : context.go(Routes.chats),
          tooltip: 'Назад',
          icon: const Icon(Icons.arrow_back),
        ),
        title: InkWell(
          onTap: () => context.push('${Routes.channel(widget.channelId)}/info'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(info?.title ?? 'Канал', maxLines: 1, overflow: TextOverflow.ellipsis),
              if (subtitle != null && subtitle.isNotEmpty)
                Text(subtitle, style: TextStyle(fontSize: 12, color: AppColors.textDim)),
            ],
          ),
        ),
        titleTextStyle: Theme.of(context).textTheme.titleLarge,
        actions: [
          if (info?.isMember ?? false)
            IconButton(
              onPressed: () => showChatNotifySheet(context, widget.channelId, info!.title),
              tooltip: 'Уведомления',
              icon: Icon(
                chatNotifyOf(ref, widget.channelId).isMuted
                    ? Icons.notifications_off_outlined
                    : Icons.notifications_active_outlined,
              ),
            ),
          IconButton(
            onPressed: () => context.push('${Routes.channel(widget.channelId)}/info'),
            tooltip: 'О канале',
            icon: const Icon(Icons.info_outline),
          ),
        ],
      ),
      body: infoAsync.when(
        loading: () => const LoadingView(),
        error: (_, _) => StateMessage.error(
          onAction: () => ref.invalidate(channelInfoProvider(widget.channelId)),
        ),
        data: (info) {
          if (info == null) {
            return const StateMessage(
              title: 'Канал не найден',
              text: 'Возможно, его удалили.',
              icon: Icons.campaign_outlined,
            );
          }
          return Column(
            children: [
              Expanded(child: info.canRead ? _posts(info) : _closed(info)),
              _bottom(info),
            ],
          );
        },
      ),
    );
  }

  Widget _posts(ChannelInfo info) {
    final posts = ref.watch(channelPostsProvider(widget.channelId));
    return posts.when(
      loading: () => const LoadingView(),
      error: (_, _) => StateMessage.error(
        onAction: () => ref.invalidate(channelPostsProvider(widget.channelId)),
      ),
      data: (items) {
        if (items.isEmpty) {
          return StateMessage(
            title: 'Постов пока нет',
            text: info.isAdmin ? 'Напишите первый — подписчики увидят его здесь.' : null,
            icon: Icons.campaign_outlined,
          );
        }
        return RefreshIndicator(
          onRefresh: () => ref.read(channelPostsProvider(widget.channelId).notifier).refreshTop(),
          child: ListView.builder(
            controller: _scroll,
            reverse: true,
            padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 8, AppSpacing.gutter, 8),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final post = items[index];
              return ChannelPostCard(
                post: post,
                onComments: () => context.push(
                  '${Routes.channel(widget.channelId)}/post/${post.message.id}',
                  extra: post,
                ),
                onLongPress: info.isAdmin ? () => _deletePost(post) : null,
              );
            },
          ),
        );
      },
    );
  }

  Widget _closed(ChannelInfo info) => StateMessage(
    icon: Icons.lock_outline,
    title: info.title,
    text: [
      if (info.description != null) info.description!,
      'Это закрытый канал. Посты видны подписчикам.',
    ].join('\n\n'),
  );

  Widget _bottom(ChannelInfo info) {
    if (info.isAdmin) {
      return ChatComposer(conversationId: widget.channelId, isDirect: false);
    }
    if (info.isMember) return const SizedBox.shrink();

    final String label;
    final bool enabled;
    if (info.isPublic || widget.inviteToken != null) {
      label = 'Подписаться';
      enabled = true;
    } else if (info.requested) {
      label = 'Заявка отправлена';
      enabled = false;
    } else {
      label = 'Подать заявку';
      enabled = true;
    }
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 8, AppSpacing.gutter, 12),
        child: FilledButton(
          onPressed: enabled && !_joining ? _join : null,
          child: _joining
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(label),
        ),
      ),
    );
  }
}

String _subscribers(int n) {
  final mod10 = n % 10;
  final mod100 = n % 100;
  final word = mod10 == 1 && mod100 != 11
      ? 'подписчик'
      : mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)
      ? 'подписчика'
      : 'подписчиков';
  return '$n $word';
}

String subscribersLabel(int n) => _subscribers(n);
