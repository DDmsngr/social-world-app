import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/errors/friendly_error.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
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

  Future<void> _sendText() async {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    await _run((repo) async {
      await repo.send(text: text);
      _text.clear();
    });
  }

  Future<void> _sendImages() async {
    final files = await _picker.pickMultiImage(imageQuality: 85);
    if (files.isEmpty) return;
    // Подпись, если она уже набрана, уходит вместе с первым снимком.
    final caption = _text.text.trim();
    await _run((repo) async {
      for (var i = 0; i < files.length; i++) {
        await repo.send(text: i == 0 ? caption : null, imagePath: files[i].path);
      }
      _text.clear();
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
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      IconButton(
                        onPressed: _busy ? null : _sendImages,
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
                        onPressed: _busy ? null : _sendText,
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
            if (message.body != null) SelectableText(message.body!),
            const SizedBox(height: 4),
            Text(
              [
                _time(message.createdAt),
                if (mine) message.handledAt == null ? 'ждёт' : 'забрал',
              ].join(' · '),
              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textFaint),
            ),
          ],
        ),
      ),
    );
  }
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
