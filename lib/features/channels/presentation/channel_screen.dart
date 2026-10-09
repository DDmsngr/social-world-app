import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'channel_article_screen.dart';

import '../../../core/debug/app_log.dart';
import '../../../core/errors/friendly_error.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/state_message.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../chat/presentation/providers/chat_extras_providers.dart';
import '../../chat/presentation/providers/chat_notify_providers.dart';
import '../../chat/presentation/widgets/message_menu.dart';
import '../../chat/presentation/providers/chat_providers.dart';
import '../../chat/presentation/widgets/chat_composer.dart';
import '../../chat/presentation/widgets/chat_notify_sheet.dart';
import '../../chat/presentation/widgets/swipe_back.dart';
import '../data/channels_repository.dart';
import 'providers/channel_providers.dart';
import 'widgets/channel_avatar.dart';
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
      final away = _scroll.position.pixels > _scroll.position.minScrollExtent + 300;
      if (away != _showDown) setState(() => _showDown = away);
    });
  }

  /// Кнопка «вниз»: видна, когда отмотали от самого свежего поста.
  var _showDown = false;

  /// Сколько новых (непрочитанных при входе) постов лежит ниже места, где
  /// остановились в прошлый раз.
  var _newerCount = 0;

  /// Отмотали выше непрочитанных — к первому непрочитанному (самому старому
  /// из новых); уже среди новых — к самому свежему. Ноль прокрутки — это
  /// нижняя кромка прежнего места: всё, что ниже (отрицательное смещение), —
  /// новые посты.
  void _scrollDown() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    final aboveUnread = _newerCount > 0 && position.pixels > 0;
    final target = aboveUnread
        // Первое непрочитанное — у верхнего края экрана.
        ? (-position.viewportDimension + 80).clamp(position.minScrollExtent, 0.0)
        : position.minScrollExtent;
    _scroll.animateTo(target, duration: const Duration(milliseconds: 400), curve: Curves.easeOutCubic);
  }

  final _probes = <_SeenProbeState>{};
  final _viewKey = GlobalKey();
  final _centerKey = GlobalKey();
  Timer? _seenTimer;
  var _bottomInset = 0.0;
  var _positioned = false;

  /// Откладывает запись «дочитал досюда»: не на каждый кадр прокрутки.
  void _scheduleSeen() {
    _seenTimer?.cancel();
    _seenTimer = Timer(const Duration(milliseconds: 500), _saveSeen);
  }

  /// Самый новый из постов, которые сейчас на экране, запоминается как место,
  /// где остановились: при возвращении лента откроется на нём, даже если
  /// новых постов набежало сотня.
  void _saveSeen({bool updateCounter = true}) {
    final box = _viewKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    final top = box.localToGlobal(Offset.zero).dy;
    final bottom = top + box.size.height - _bottomInset;
    DateTime? newest;
    for (final probe in _probes) {
      final item = probe.context.findRenderObject();
      if (item is! RenderBox || !item.attached || !item.hasSize) continue;
      final itemTop = item.localToGlobal(Offset.zero).dy;
      final itemBottom = itemTop + item.size.height;
      // Пост считается увиденным, когда на экране его заметная часть.
      if (itemTop < bottom - 24 && itemBottom > top + 24) {
        final at = probe.widget.sentAt;
        if (newest == null || at.isAfter(newest)) newest = at;
      }
    }
    if (newest != null) {
      ChannelSeen.save(widget.channelId, newest);
      _markRead(newest);
      // Счётчик у кнопки «вниз»: сколько постов ниже самого свежего из тех,
      // что сейчас на экране, — ещё не виденные. Уменьшается по мере прокрутки.
      final below = _items.where((p) => p.message.sentAt.isAfter(newest!)).length;
      if (updateCounter && below != _unreadBelow && mounted) setState(() => _unreadBelow = below);
    }
  }

  /// Посты ленты (от новых к старым) — для счётчика непрочитанных ниже.
  List<ChannelPost> _items = const [];
  var _unreadBelow = 0;

  @override
  void deactivate() {
    // Уходим с экрана: фиксируем место, пока карточки ещё в дереве.
    _seenTimer?.cancel();
    // Дерево уже разбирается — перерисовывать счётчик нельзя.
    _saveSeen(updateCounter: false);
    super.deactivate();
  }

  @override
  void dispose() {
    _seenTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  DateTime? _markedUntil;

  /// Прочитано на сервере до самого свежего поста, побывавшего на экране, —
  /// тогда счётчик в списке каналов совпадает с непрочитанными внутри.
  Future<void> _markRead(DateTime until) async {
    if (!(ref.read(channelInfoProvider(widget.channelId)).value?.isMember ?? false)) return;
    final marked = _markedUntil;
    if (marked != null && !until.isAfter(marked)) return;
    _markedUntil = until;
    // Вызывается и при уходе с экрана: после await ref экрана уже мёртв,
    // поэтому список чатов освежаем через контейнер, взятый заранее.
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      await container.read(channelsRepositoryProvider).markRead(widget.channelId, until);
      container.invalidate(conversationsProvider);
    } catch (error) {
      _markedUntil = marked;
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

  String? _myReaction(String messageId) {
    final list = ref.read(chatReactionsProvider(widget.channelId)).value?[messageId];
    for (final r in list ?? const <ReactionCount>[]) {
      if (r.mine) return r.emoji;
    }
    return null;
  }

  Future<void> _react(String messageId, String emoji) async {
    unawaited(ReactionUsage.record(emoji));
    try {
      await toggleReaction(ref, widget.channelId, messageId, emoji);
    } catch (error) {
      AppLog.add('Реакция на пост: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(error, fallback: 'Не удалось поставить реакцию'))),
      );
    }
  }

  Future<void> _quickReact(BuildContext cardContext, ChannelPost post) async {
    final emoji = await showReactionPicker(
      cardContext,
      mine: false,
      myReaction: _myReaction(post.message.id),
    );
    if (emoji != null) await _react(post.message.id, emoji);
  }

  Future<void> _openMenu(BuildContext cardContext, ChannelPost post) async {
    final gone = await showMessageMenu(
      cardContext,
      ref,
      message: post.message,
      myId: ref.read(currentUserProvider)?.id ?? '',
      conversation: ref.read(conversationProvider(widget.channelId)).value,
      myReaction: _myReaction(post.message.id),
      onReact: (emoji) => _react(post.message.id, emoji),
    );
    // Удалили (или скрыли у себя): пост уходит из ленты сразу.
    if (gone && mounted) {
      ref.read(channelPostsProvider(widget.channelId).notifier).remove(post.message.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final infoAsync = ref.watch(channelInfoProvider(widget.channelId));
    final info = infoAsync.value;

    // Подписчик получает новые посты реалтаймом чатов: на каждое изменение
    // ленты подтягиваем верх. Прочитанным пост отмечается, только когда
    // побывал на экране (_saveSeen).
    if (info?.isMember ?? false) {
      ref.listen(messagesProvider(widget.channelId), (_, next) {
        if (next.hasValue) {
          ref.read(channelPostsProvider(widget.channelId).notifier).refreshTop();
        }
      });
    }

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
          child: Row(
            children: [
              ChannelAvatar(url: info?.avatarUrl, radius: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(info?.title ?? 'Канал', maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (subtitle != null && subtitle.isNotEmpty)
                      Text(subtitle, style: TextStyle(fontSize: 12, color: AppColors.textDim)),
                  ],
                ),
              ),
            ],
          ),
        ),
        titleTextStyle: Theme.of(context).textTheme.titleLarge,
        actions: [
          // Подписка всегда на виду: в шапке и внизу экрана.
          if (info != null && !info.isMember && (info.isPublic || widget.inviteToken != null))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: FilledButton(
                onPressed: _joining ? null : _join,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                child: const Text('Подписаться'),
              ),
            ),
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
              Expanded(
                child: SwipeBackToExit(
                  onExit: () => context.canPop() ? context.pop() : context.go(Routes.chats),
                  child: info.canRead ? _posts(info) : _closed(info),
                ),
              ),
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
        // Без поля ввода снизу (читатель-подписчик) лента идёт под
        // стеклянную панель вкладок — оставляем под неё место.
        _bottomInset = info.isMember && !info.isAdmin ? MediaQuery.paddingOf(context).bottom : 0;
        final anchor = ref.read(channelPostsProvider(widget.channelId).notifier).anchor;
        // items — от новых к старым. Если открываемся на прежнем месте, то
        // якорь и всё старше него растёт вверх от нижней кромки экрана, а
        // новые посты лежат ниже и открываются прокруткой вниз.
        final newer = anchor == null
            ? const <ChannelPost>[]
            : [for (final p in items.reversed) if (p.message.sentAt.isAfter(anchor)) p];
        final older = anchor == null
            ? items
            : [for (final p in items) if (!p.message.sentAt.isAfter(anchor)) p];
        _newerCount = newer.length;
        _items = items;

        final reactions = ref.watch(chatReactionsProvider(widget.channelId)).value ?? const {};

        SliverList list(List<ChannelPost> posts) => SliverList(
          delegate: SliverChildBuilderDelegate(
            childCount: posts.length,
            // Ключ по id поста: новые посты встают в ленту, и без ключей
            // состояние карточек (загруженное видео, фото) съезжало бы на
            // соседний пост.
            findChildIndexCallback: (key) {
              if (key is! ValueKey<String>) return null;
              final at = posts.indexWhere((p) => p.message.id == key.value);
              return at < 0 ? null : at;
            },
            (context, index) {
              final post = posts[index];
              return _SeenProbe(
                key: ValueKey(post.message.id),
                registry: _probes,
                sentAt: post.message.sentAt,
                child: ChannelPostCard(
                  post: post,
                  onComments: () => context.push(
                    '${Routes.channel(widget.channelId)}/post/${post.message.id}',
                    extra: post,
                  ),
                  reactions: reactions[post.message.id] ?? const [],
                  onReact: (emoji) => _react(post.message.id, emoji),
                  // Короткий тап — реакции у самого поста, долгий — меню:
                  // поделиться, сохранить, закладка (только в этом канале) и т. д.
                  onTap: (cardContext) => _quickReact(cardContext, post),
                  onLongPress: (cardContext) => _openMenu(cardContext, post),
                ),
              );
            },
          ),
        );

        // Открылись на прежнем месте: якорь приподнимаем над нижней кромкой
        // (там стеклянная панель), чтобы снизу виднелись новые посты.
        if (anchor != null && !_positioned) {
          _positioned = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!_scroll.hasClients) return;
            final target = -(120 + _bottomInset);
            _scroll.jumpTo(target < _scroll.position.minScrollExtent
                ? _scroll.position.minScrollExtent
                : target);
          });
        }

        _scheduleSeen();
        final feed = RefreshIndicator(
          onRefresh: () => ref.read(channelPostsProvider(widget.channelId).notifier).refreshTop(),
          child: NotificationListener<ScrollNotification>(
            onNotification: (_) {
              _scheduleSeen();
              return false;
            },
            child: KeyedSubtree(
              key: _viewKey,
              child: CustomScrollView(
                controller: _scroll,
                reverse: true,
                center: _centerKey,
                slivers: [
                  if (newer.isNotEmpty)
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(AppSpacing.gutter, 0, AppSpacing.gutter, 8 + _bottomInset),
                      sliver: list(newer),
                    ),
                  SliverPadding(
                    key: _centerKey,
                    padding: EdgeInsets.fromLTRB(
                      AppSpacing.gutter,
                      8,
                      AppSpacing.gutter,
                      newer.isEmpty ? 8 + _bottomInset : 0,
                    ),
                    sliver: list(older),
                  ),
                ],
              ),
            ),
          ),
        );
        return Stack(
          children: [
            Positioned.fill(child: feed),
            Positioned(
              right: 16,
              bottom: 16 + _bottomInset,
              child: AnimatedScale(
                scale: _showDown ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                child: Badge(
                  isLabelVisible: _unreadBelow > 0,
                  label: Text(_unreadBelow > 99 ? '99+' : '$_unreadBelow'),
                  backgroundColor: AppColors.primaryTint,
                  offset: const Offset(-4, -6),
                  child: FloatingActionButton.small(
                    heroTag: null,
                    onPressed: _scrollDown,
                    tooltip: 'Вниз',
                    backgroundColor: AppColors.card,
                    foregroundColor: AppColors.text,
                    child: const Icon(Icons.keyboard_arrow_down),
                  ),
                ),
              ),
            ),
          ],
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
      // Два формата: короткий пост — полем ввода, статья с фото посреди
      // текста — отдельным редактором.
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: TextButton.icon(
                onPressed: () async {
                  final published = await Navigator.of(context, rootNavigator: true).push<bool>(
                    MaterialPageRoute(builder: (_) => ChannelArticleScreen(channelId: widget.channelId)),
                  );
                  if (published == true) {
                    ref.read(channelPostsProvider(widget.channelId).notifier).refreshTop();
                  }
                },
                icon: const Icon(Icons.article_outlined, size: 18),
                label: const Text('Статья с фото'),
              ),
            ),
          ),
          ChatComposer(conversationId: widget.channelId, isDirect: false, isChannel: true),
        ],
      );
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

/// Метка у карточки поста: экран спрашивает у них, какие сейчас на виду.
class _SeenProbe extends StatefulWidget {
  const _SeenProbe({
    super.key,
    required this.registry,
    required this.sentAt,
    required this.child,
  });

  final Set<_SeenProbeState> registry;
  final DateTime sentAt;
  final Widget child;

  @override
  State<_SeenProbe> createState() => _SeenProbeState();
}

class _SeenProbeState extends State<_SeenProbe> {
  @override
  void initState() {
    super.initState();
    widget.registry.add(this);
  }

  @override
  void dispose() {
    widget.registry.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
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
