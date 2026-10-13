import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/friendly_error.dart';
import '../../../core/widgets/state_message.dart';
import '../../../core/widgets/user_avatar.dart';
import '../data/channels_repository.dart';
import 'providers/channel_providers.dart';

/// Кто подписан на канал. Открывается из «О канале», только у администраторов.
class ChannelSubscribersScreen extends ConsumerStatefulWidget {
  const ChannelSubscribersScreen({super.key, required this.channelId});

  final String channelId;

  @override
  ConsumerState<ChannelSubscribersScreen> createState() => _ChannelSubscribersScreenState();
}

class _ChannelSubscribersScreenState extends ConsumerState<ChannelSubscribersScreen> {
  List<Subscriber>? _items;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final items = await ref.read(channelsRepositoryProvider).subscribers(widget.channelId);
      if (mounted) setState(() => _items = items);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final Widget body;
    if (_error != null) {
      body = StateMessage(
        icon: Icons.error_outline,
        title: friendlyError(_error!, fallback: 'Не удалось загрузить подписчиков'),
        actionLabel: 'Повторить',
        onAction: _load,
      );
    } else if (items == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: items.length,
          itemBuilder: (context, i) {
            final s = items[i];
            return ListTile(
              contentPadding: EdgeInsets.zero,
              onTap: () => openProfile(context, s.profileId),
              leading: UserAvatar(name: s.name, url: s.avatarUrl),
              title: Text(s.name),
              subtitle: Text(
                s.role == 'owner'
                    ? 'Владелец'
                    : s.role == 'admin'
                    ? 'Администратор · с ${_date(s.joinedAt)}'
                    : 'Подписан с ${_date(s.joinedAt)}',
              ),
            );
          },
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(items == null ? 'Подписчики' : 'Подписчики · ${items.length}')),
      body: body,
    );
  }
}

String _date(DateTime time) {
  const months = [
    'янв', 'фев', 'мар', 'апр', 'мая', 'июн',
    'июл', 'авг', 'сен', 'окт', 'ноя', 'дек',
  ];
  return '${time.day} ${months[time.month - 1]} ${time.year}';
}
