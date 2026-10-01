import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/debug/app_log.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/state_message.dart';
import '../../chat/presentation/providers/chat_notify_providers.dart';
import '../../chat/presentation/providers/chat_providers.dart';
import '../data/channels_repository.dart';
import 'channel_screen.dart';
import 'providers/channel_providers.dart';

/// Каталог публичных каналов: поиск, темы, подписка одним касанием.
class ChannelCatalogScreen extends ConsumerStatefulWidget {
  const ChannelCatalogScreen({super.key});

  @override
  ConsumerState<ChannelCatalogScreen> createState() => _ChannelCatalogScreenState();
}

class _ChannelCatalogScreenState extends ConsumerState<ChannelCatalogScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  ChannelTopic? _topic;
  List<CatalogChannel>? _items;
  var _failed = false;
  final _busy = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    try {
      final items = await ref
          .read(channelsRepositoryProvider)
          .search(query: _search.text, topic: _topic);
      if (mounted) setState(() => _items = items);
    } catch (error) {
      AppLog.add('Каталог каналов: $error');
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _subscribe(CatalogChannel channel) async {
    setState(() => _busy.add(channel.id));
    try {
      await ref.read(channelsRepositoryProvider).join(channel.id);
      ref.invalidate(conversationsProvider);
      ref.invalidate(chatNotifyProvider);
      await _load();
    } catch (error) {
      AppLog.add('Подписка на канал: $error');
    } finally {
      if (mounted) setState(() => _busy.remove(channel.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Каналы'),
        leading: IconButton(
          onPressed: () => context.canPop() ? context.pop() : context.go(Routes.chats),
          tooltip: 'Назад',
          icon: const Icon(Icons.arrow_back),
        ),
        actions: [
          IconButton(
            onPressed: () => context.push(Routes.newChannel),
            tooltip: 'Создать канал',
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 8, AppSpacing.gutter, 4),
            child: TextField(
              controller: _search,
              onChanged: (_) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 350), _load);
              },
              decoration: const InputDecoration(
                hintText: 'Название или @адрес',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
              children: [
                for (final topic in [null, ...ChannelTopic.values])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(topic?.label ?? 'Все темы'),
                      selected: _topic == topic,
                      onSelected: (_) {
                        setState(() => _topic = topic);
                        _load();
                      },
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _failed
                ? StateMessage.error(onAction: _load)
                : items == null
                ? const LoadingView()
                : items.isEmpty
                ? const StateMessage(
                    title: 'Ничего не нашлось',
                    icon: Icons.campaign_outlined,
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.separated(
                      padding: AppSpacing.page(context, top: 4),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const Divider(),
                      itemBuilder: (context, index) => _tile(items[index]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _tile(CatalogChannel channel) {
    final meta = [
      if (channel.handle != null) '@${channel.handle}',
      channel.topic.label,
      if (channel.subscriberCount != null) subscribersLabel(channel.subscriberCount!),
    ].join(' · ');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: () => context.push(Routes.channel(channel.id)),
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: AppColors.ink,
        child: Icon(Icons.campaign_outlined, color: AppColors.champagne, size: 20),
      ),
      title: Text(channel.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(meta, style: TextStyle(fontSize: 12, color: AppColors.textDim)),
          if (channel.description != null)
            Text(channel.description!, maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
      ),
      trailing: channel.joined
          ? Icon(Icons.check, color: AppColors.textFaint)
          : FilledButton.tonal(
              style: AppButtons.compact,
              onPressed: _busy.contains(channel.id) ? null : () => _subscribe(channel),
              child: const Text('Подписаться'),
            ),
    );
  }
}
