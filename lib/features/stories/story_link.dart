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
  final id = replyMessageId.substring(storyReplyPrefix.length);
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
