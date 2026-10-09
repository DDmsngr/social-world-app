import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/debug/app_log.dart';
import '../../../core/errors/friendly_error.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/sw_widgets.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../profile/domain/profile_models.dart';
import '../../profile/presentation/providers/profile_providers.dart';
import '../domain/entities/conversation.dart';
import 'providers/chat_providers.dart';

/// Поиск из вкладки «Чаты»: сначала среди своих переписок, ниже — люди в
/// ChaWo (написать им можно прямо отсюда), и отдельной строкой — «Из
/// записной книжки». Каналы ищутся в своём каталоге (значок на вкладке
/// «Каналы»).
class ChatSearchScreen extends ConsumerStatefulWidget {
  const ChatSearchScreen({super.key});

  @override
  ConsumerState<ChatSearchScreen> createState() => _ChatSearchScreenState();
}

class _ChatSearchScreenState extends ConsumerState<ChatSearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  var _query = '';
  List<ProfileHit> _people = const [];
  var _searching = false;
  var _failed = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    setState(() => _query = value.trim());
    _debounce?.cancel();
    if (value.trim().length < 2) {
      setState(() {
        _people = const [];
        _searching = false;
        _failed = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), _searchPeople);
  }

  Future<void> _searchPeople() async {
    final query = _query;
    setState(() {
      _searching = true;
      _failed = false;
    });
    try {
      final hits = await ref.read(profileRepositoryProvider).searchProfiles(query);
      if (!mounted || query != _query) return;
      setState(() {
        _people = hits;
        _searching = false;
      });
    } catch (error) {
      AppLog.add('Поиск людей: $error');
      if (mounted) {
        setState(() {
          _searching = false;
          _failed = true;
        });
      }
    }
  }

  Future<void> _write(ProfileHit person) async {
    try {
      final id = await ref.read(chatRepositoryProvider).openDirect(person.id);
      if (mounted) context.go('${Routes.chats}/$id', extra: person.displayName);
    } catch (error) {
      AppLog.add('Диалог не открылся: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyError(error, fallback: 'Не удалось открыть переписку')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final lower = _query.toLowerCase();
    final chats = [
      for (final c in ref.watch(conversationsProvider).value ?? const <Conversation>[])
        if (!c.isChannel && lower.isNotEmpty && c.displayName.toLowerCase().contains(lower)) c,
    ];

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => context.canPop() ? context.pop() : context.go(Routes.chats),
          tooltip: 'Назад',
          icon: const Icon(Icons.arrow_back),
        ),
        title: TextField(
          controller: _controller,
          autofocus: true,
          onChanged: _onChanged,
          decoration: const InputDecoration(
            hintText: 'Имя человека или название чата',
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
          ),
        ),
      ),
      body: ListView(
        padding: AppSpacing.page(context, top: 8),
        children: [
          GlassCard(
            padding: const EdgeInsets.all(14),
            onTap: () => context.push(Routes.inviteContacts),
            child: Row(
              children: [
                Icon(Icons.contacts_outlined, color: AppColors.primaryTint),
                const SizedBox(width: 14),
                const Expanded(child: Text('Из записной книжки: кто уже в ChaWo, кого позвать')),
                Icon(Icons.chevron_right, color: AppColors.textFaint),
              ],
            ),
          ),
          if (chats.isNotEmpty) ...[
            const SizedBox(height: 16),
            const SectionLabel('Ваши чаты'),
            for (final c in chats)
              ListTile(
                contentPadding: EdgeInsets.zero,
                onTap: () => context.push('${Routes.chats}/${c.id}', extra: c.displayName),
                leading: c.isDirect
                    ? UserAvatar(name: c.displayName, url: c.peerAvatarUrl)
                    : CircleAvatar(
                        backgroundColor: AppColors.ink2,
                        child: Icon(Icons.group_outlined, color: AppColors.primaryTint),
                      ),
                title: Text(c.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
          ],
          const SizedBox(height: 16),
          const SectionLabel('Люди в ChaWo'),
          if (_query.length < 2)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'Введите хотя бы две буквы имени или @ник.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            )
          else if (_searching)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_failed)
            TextButton(onPressed: _searchPeople, child: const Text('Не загрузилось. Повторить'))
          else if (_people.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text('Никого не нашлось.', style: Theme.of(context).textTheme.bodyMedium),
            )
          else
            for (final person in _people)
              ListTile(
                contentPadding: EdgeInsets.zero,
                onTap: () => openProfile(context, person.id),
                leading: UserAvatar(name: person.displayName, url: person.avatarUrl),
                title: Text(person.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: person.username != null
                    ? Text('@${person.username}')
                    : (person.followedByMe ? const Text('Вы подписаны') : null),
                trailing: IconButton(
                  onPressed: () => _write(person),
                  tooltip: 'Написать',
                  icon: Icon(Icons.chat_bubble_outline, color: AppColors.primaryTint),
                ),
              ),
        ],
      ),
    );
  }
}
