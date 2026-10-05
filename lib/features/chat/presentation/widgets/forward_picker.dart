import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/debug/app_log.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/forward_service.dart';
import '../providers/chat_providers.dart';

/// Выбор чатов для пересылки. Возвращает итог или null, если закрыли.
///
/// Сама отправка идёт внутри листа — с индикатором, чтобы человек видел, что
/// файлы качаются и уходят, а не думал, что кнопка не сработала.
Future<ForwardResult?> showForwardPicker(
  BuildContext context, {
  required List<ChatMessage> messages,
  required String Function(ChatMessage message) authorOf,
  String? excludeConversationId,
  bool withAuthor = true,
  String? title,
}) => showModalBottomSheet<ForwardResult>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  backgroundColor: AppColors.ink2,
  showDragHandle: true,
  builder: (_) => _ForwardSheet(
    messages: messages,
    authorOf: authorOf,
    excludeConversationId: excludeConversationId,
    withAuthor: withAuthor,
    title: title,
  ),
);

/// Сообщение для снекбара после пересылки.
String forwardSummary(ForwardResult result, List<Conversation> all) {
  String name(String id) =>
      all.where((c) => c.id == id).firstOrNull?.displayName ?? 'чат';
  if (result.failed.isEmpty) {
    return result.delivered.length == 1
        ? 'Переслано: ${name(result.delivered.first)}'
        : 'Переслано в ${result.delivered.length} чатов';
  }
  final failed = result.failed.keys.map(name).join(', ');
  return result.delivered.isEmpty
      ? 'Не удалось переслать: $failed'
      : 'Переслано в ${result.delivered.length}, не вышло: $failed';
}

class _ForwardSheet extends ConsumerStatefulWidget {
  const _ForwardSheet({
    required this.messages,
    required this.authorOf,
    this.excludeConversationId,
    this.withAuthor = true,
    this.title,
  });

  final List<ChatMessage> messages;
  final String Function(ChatMessage message) authorOf;
  final String? excludeConversationId;
  final bool withAuthor;
  final String? title;

  @override
  ConsumerState<_ForwardSheet> createState() => _ForwardSheetState();
}

class _ForwardSheetState extends ConsumerState<_ForwardSheet> {
  /// Больше — это уже рассылка, а не пересылка.
  static const _maxTargets = 10;

  final _selected = <String>{};
  var _query = '';
  var _busy = false;

  Future<void> _send(List<Conversation> all) async {
    setState(() => _busy = true);
    try {
      final result = await forwardMessages(
        repository: ref.read(chatRepositoryProvider),
        messages: widget.messages,
        targets: [
          for (final c in all)
            if (_selected.contains(c.id)) c,
        ],
        authorOf: widget.authorOf,
        withAuthor: widget.withAuthor,
      );
      ref.invalidate(conversationsProvider);
      if (mounted) Navigator.of(context).pop(result);
    } catch (error) {
      AppLog.add('Пересылка: $error');
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final conversations = ref.watch(conversationsProvider);
    final height = MediaQuery.sizeOf(context).height * 0.8;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.gutter,
                0,
                AppSpacing.gutter,
                10,
              ),
              child: Text(
                widget.title ??
                    (widget.withAuthor ? 'Переслать' : 'Изменить и переслать'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
              child: TextField(
                onChanged: (value) => setState(() => _query = value.trim()),
                decoration: const InputDecoration(
                  hintText: 'Поиск по чатам',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: conversations.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) => const Center(
                  child: Text('Не удалось загрузить чаты'),
                ),
                data: (all) {
                  // Закрытый чат (квест завершён) принимать сообщения не
                  // может; чат, из которого пересылаем, — тоже не нужен.
                  final available = [
                    for (final c in all)
                      if (!c.closed &&
                          c.canPost &&
                          c.id != widget.excludeConversationId &&
                          (_query.isEmpty ||
                              c.displayName.toLowerCase().contains(
                                _query.toLowerCase(),
                              )))
                        c,
                  ];
                  if (available.isEmpty) {
                    return Center(
                      child: Text(
                        _query.isEmpty
                            ? 'Других чатов пока нет'
                            : 'Ничего не нашлось',
                        style: TextStyle(color: AppColors.textDim),
                      ),
                    );
                  }
                  return Column(
                    children: [
                      Expanded(
                        child: ListView.builder(
                          itemCount: available.length,
                          itemBuilder: (context, index) {
                            final c = available[index];
                            final checked = _selected.contains(c.id);
                            return CheckboxListTile(
                              value: checked,
                              onChanged: _busy
                                  ? null
                                  : (value) => setState(() {
                                      if (value == true) {
                                        if (_selected.length < _maxTargets) {
                                          _selected.add(c.id);
                                        }
                                      } else {
                                        _selected.remove(c.id);
                                      }
                                    }),
                              activeColor: AppColors.primaryTint,
                              checkColor: AppColors.ink,
                              controlAffinity: ListTileControlAffinity.trailing,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.gutter,
                              ),
                              secondary: c.isDirect
                                  ? UserAvatar(
                                      name: c.displayName,
                                      url: c.peerAvatarUrl,
                                      radius: 20,
                                    )
                                  : CircleAvatar(
                                      radius: 20,
                                      backgroundColor: AppColors.ink,
                                      child: Icon(
                                        c.kind == ConversationKind.quest
                                            ? Icons.flag_outlined
                                            : Icons.group_outlined,
                                        color: AppColors.primaryTint,
                                        size: 20,
                                      ),
                                    ),
                              title: Text(
                                c.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          },
                        ),
                      ),
                      SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.gutter),
                          child: SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: _selected.isEmpty || _busy
                                  ? null
                                  : () => _send(all),
                              child: _busy
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text(
                                      _selected.isEmpty
                                          ? 'Выберите чат'
                                          : 'Переслать (${_selected.length})',
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
