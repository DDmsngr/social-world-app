import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/debug/app_log.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/state_message.dart';
import '../../../core/widgets/user_avatar.dart';
import '../domain/profile_models.dart';
import 'providers/profile_providers.dart';

/// Подписчики или подписки человека. Список догружается страницами по 50.
class FollowListScreen extends ConsumerStatefulWidget {
  const FollowListScreen({super.key, required this.userId, required this.list});

  final String userId;
  final FollowList list;

  @override
  ConsumerState<FollowListScreen> createState() => _FollowListScreenState();
}

class _FollowListScreenState extends ConsumerState<FollowListScreen> {
  static const _pageSize = 50;

  final _items = <ProfileHit>[];
  bool _loading = true;
  bool _failed = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final page = await ref
          .read(profileRepositoryProvider)
          .loadFollowList(widget.userId, widget.list, offset: _items.length);
      if (!mounted) return;
      setState(() {
        _items.addAll(page);
        _hasMore = page.length == _pageSize;
        _loading = false;
      });
    } catch (error) {
      AppLog.add('Список подписок не загрузился: $error');
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final followers = widget.list == FollowList.followers;

    Widget body;
    if (_items.isEmpty && _loading) {
      body = const LoadingView();
    } else if (_items.isEmpty && _failed) {
      body = StateMessage.error(onAction: _load);
    } else if (_items.isEmpty) {
      body = StateMessage(
        title: followers ? 'Подписчиков пока нет' : 'Подписок пока нет',
        icon: Icons.people_outline,
      );
    } else {
      body = ListView.separated(
        padding: AppSpacing.page(context),
        itemCount: _items.length + (_hasMore || _failed ? 1 : 0),
        separatorBuilder: (_, _) => const Divider(),
        itemBuilder: (context, index) {
          if (index == _items.length) {
            return Center(
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(),
                    )
                  : TextButton(
                      onPressed: _load,
                      child: Text(_failed ? 'Повторить' : 'Показать ещё'),
                    ),
            );
          }
          final item = _items[index];
          return ListTile(
            contentPadding: EdgeInsets.zero,
            onTap: () => openProfile(context, item.id),
            leading: UserAvatar(name: item.displayName, url: item.avatarUrl),
            title: Text(item.displayName),
            subtitle: item.followedByMe ? const Text('Вы подписаны') : null,
          );
        },
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(followers ? 'Подписчики' : 'Подписки'),
        leading: IconButton(
          onPressed: () =>
              context.canPop() ? context.pop() : context.go(Routes.home),
          tooltip: 'Назад',
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: body,
    );
  }
}
