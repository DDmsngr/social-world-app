import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/debug/app_log.dart';
import '../../core/errors/friendly_error.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/link_text.dart';
import '../../core/widgets/state_message.dart';
import 'assistant.dart';

/// Профиль → Помощник. Сюда владелец проекта скидывает правки и скриншоты;
/// Claude забирает их из сессии и отвечает здесь же.
class AssistantScreen extends ConsumerStatefulWidget {
  const AssistantScreen({super.key});

  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends ConsumerState<AssistantScreen> {
  final _text = TextEditingController();
  final _picker = ImagePicker();
  var _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function(AssistantRepository repo) job) async {
    final repo = ref.read(assistantRepositoryProvider);
    if (repo == null || _busy) return;
    setState(() => _busy = true);
    try {
      await job(repo);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(error, fallback: 'Не отправилось'))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Приложенные, но ещё не отправленные снимки.
  final _pending = <String>[];

  Future<void> _attach() async {
    final files = await _picker.pickMultiImage(imageQuality: 85);
    if (files.isEmpty || !mounted) return;
    setState(() => _pending.addAll(files.map((f) => f.path)));
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    if (text.isEmpty && _pending.isEmpty) return;
    final shots = [..._pending];
    await _run((repo) async {
      // Подпись уходит вместе с первым снимком, остальные — следом.
      if (shots.isEmpty) {
        await repo.send(text: text);
      } else {
        for (var i = 0; i < shots.length; i++) {
          await repo.send(text: i == 0 ? text : null, imagePath: shots[i]);
        }
      }
      _text.clear();
      if (mounted) setState(_pending.clear);
    });
  }

  @override
  Widget build(BuildContext context) {
    final owner = ref.watch(isAssistantOwnerProvider);
    final messages = ref.watch(assistantMessagesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Помощник'),
        leading: IconButton(
          onPressed: () =>
              context.canPop() ? context.pop() : context.go(Routes.profile),
          tooltip: 'Назад',
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: owner.when(
        loading: () => const LoadingView(),
        error: (_, _) => const StateMessage(
          title: 'Не открылось',
          text: 'Попробуйте позже.',
          icon: Icons.error_outline,
        ),
        data: (isOwner) {
          if (!isOwner) {
            return const StateMessage(
              title: 'Недоступно',
              text: 'Этот раздел открыт только владельцу проекта.',
              icon: Icons.lock_outline,
            );
          }
          return Column(
            children: [
              Expanded(
                child: messages.when(
                  loading: () => const LoadingView(),
                  error: (_, _) => StateMessage.error(
                    onAction: () => ref.invalidate(assistantMessagesProvider),
                  ),
                  data: (list) => list.isEmpty
                      ? const StateMessage(
                          title: 'Пока пусто',
                          text: 'Пишите правки и прикладывайте скриншоты. '
                              'Помощник заберёт их, когда будет на связи.',
                          icon: Icons.support_agent,
                        )
                      : ListView.builder(
                          reverse: true,
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                          itemCount: list.length,
                          itemBuilder: (_, index) =>
                              _Bubble(message: list[list.length - 1 - index]),
                        ),
                ),
              ),
              if (_pending.isNotEmpty)
                SizedBox(
                  height: 84,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                    itemCount: _pending.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (_, i) => Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.file(
                            File(_pending[i]),
                            width: 72,
                            height: 72,
                            fit: BoxFit.cover,
                            cacheWidth: 216,
                          ),
                        ),
                        Positioned(
                          right: 0,
                          top: 0,
                          child: GestureDetector(
                            onTap: _busy ? null : () => setState(() => _pending.removeAt(i)),
                            child: const CircleAvatar(
                              radius: 11,
                              backgroundColor: Colors.black54,
                              child: Icon(Icons.close, size: 14, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      IconButton(
                        onPressed: _busy ? null : _attach,
                        tooltip: 'Скриншоты',
                        icon: const Icon(Icons.attach_file),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _text,
                          minLines: 1,
                          maxLines: 6,
                          maxLength: 4000,
                          buildCounter: (_, {required currentLength, required isFocused, maxLength}) =>
                              null,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(hintText: 'Что поправить'),
                        ),
                      ),
                      IconButton(
                        onPressed: _busy ? null : _send,
                        tooltip: 'Отправить',
                        icon: _busy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(Icons.send, color: AppColors.primary),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Bubble extends ConsumerWidget {
  const _Bubble({required this.message});

  final AssistantMessage message;

  void _toast(BuildContext context, String text) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(text: message.body);
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Изменить сообщение'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 10,
          maxLength: 4000,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (text == null || text.trim() == message.body) return;
    try {
      await ref.read(assistantRepositoryProvider)!.edit(message.id, text);
    } catch (error) {
      AppLog.add('Сообщение Помощнику не изменилось: $error');
      if (context.mounted) _toast(context, 'Не получилось — возможно, Помощник уже забрал его');
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить сообщение?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Удалить')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(assistantRepositoryProvider)!.delete(message.id);
    } catch (error) {
      AppLog.add('Сообщение Помощнику не удалилось: $error');
      if (context.mounted) _toast(context, 'Не получилось — возможно, Помощник уже забрал его');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mine = message.fromUser;
    final theme = Theme.of(context);
    final path = message.attachmentPath;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.all(10),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
        decoration: BoxDecoration(
          color: mine ? AppColors.primary.withValues(alpha: 0.16) : AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.hair),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (path != null) _Shot(path: path),
            if (path != null && message.body != null) const SizedBox(height: 6),
            if (message.body != null) LinkText(message.body!, selectable: true),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  [
                    _time(message.createdAt),
                    if (mine) message.handledAt == null ? 'ждёт' : 'забрал',
                  ].join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textFaint),
                ),
                // Пока Помощник не забрал сообщение, его можно поправить.
                if (mine && message.handledAt == null) ...[
                  if (message.body != null)
                    _SmallAction(
                      icon: Icons.edit_outlined,
                      tooltip: 'Изменить',
                      onTap: () => _edit(context, ref),
                    ),
                  _SmallAction(
                    icon: Icons.delete_outline,
                    tooltip: 'Удалить',
                    onTap: () => _delete(context, ref),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SmallAction extends StatelessWidget {
  const _SmallAction({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Icon(icon, size: 16, color: AppColors.textDim),
      ),
    ),
  );
}

String _time(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(t.day)}.${two(t.month)} ${two(t.hour)}:${two(t.minute)}';
}

class _Shot extends ConsumerWidget {
  const _Shot({required this.path});

  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(assistantRepositoryProvider);
    if (repo == null) return const SizedBox.shrink();
    return FutureBuilder<String>(
      future: repo.signedUrl(path),
      builder: (_, snap) {
        final url = snap.data;
        if (url == null) {
          return SizedBox(
            height: 120,
            child: Center(
              child: snap.hasError
                  ? Icon(Icons.broken_image_outlined, color: AppColors.textFaint)
                  : const CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.network(url, fit: BoxFit.contain, height: 220),
        );
      },
    );
  }
}
