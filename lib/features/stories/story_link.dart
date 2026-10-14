import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/debug/app_log.dart';
import 'stories.dart';
import 'story_viewer.dart';

/// Id цитаты, которой ответ на блик помечает исходную историю.
const storyReplyPrefix = 'story-';

/// Ответ на блик в чате несёт цитату с id `story-<id>`. Тап по ней открывает
/// этот самый блик, пока он ещё живёт (истории исчезают через сутки) — иначе
/// говорим, что его уже нет, а не молчим.
Future<void> openStoryFromReply(BuildContext context, WidgetRef ref, String replyMessageId) async {
  if (!replyMessageId.startsWith(storyReplyPrefix)) return;
  await openStoryById(context, ref, replyMessageId.substring(storyReplyPrefix.length));
}

/// Открыть один блик по id: из цитаты в чате или из уведомления об
/// упоминании. Блика уже нет (живут сутки) — так и говорим.
Future<void> openStoryById(BuildContext context, WidgetRef ref, String id) async {
  final messenger = ScaffoldMessenger.of(context);
  Story? found;
  StoryGroup? group;
  try {
    final controller = ref.read(storiesProvider.notifier);
    await controller.refresh();
    for (final g in ref.read(storiesProvider).value ?? const <StoryGroup>[]) {
      for (final s in g.stories) {
        if (s.id == id) {
          found = s;
          group = g;
        }
      }
    }
  } catch (error) {
    AppLog.add('Блик из цитаты не нашёлся: $error');
  }
  if (!context.mounted) return;
  if (found == null || group == null) {
    messenger.showSnackBar(const SnackBar(content: Text('Этого блика уже нет')));
    return;
  }
  // Показываем именно его: группа из одной истории, чтобы просмотр не начался
  // с первой непросмотренной у этого автора.
  await showStories(
    context,
    groups: [group.copyWith(stories: [found])],
    initialGroup: 0,
  );
}

/// Экран-переходник для адреса `/stories/<id>` (уведомление об упоминании):
/// открывает просмотр блика и закрывается, когда его закрыли.
class StoryOpenScreen extends ConsumerStatefulWidget {
  const StoryOpenScreen({super.key, required this.storyId});

  final String storyId;

  @override
  ConsumerState<StoryOpenScreen> createState() => _StoryOpenScreenState();
}

class _StoryOpenScreenState extends ConsumerState<StoryOpenScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await openStoryById(context, ref, widget.storyId);
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(
    backgroundColor: Colors.black,
    body: Center(child: CircularProgressIndicator()),
  );
}
