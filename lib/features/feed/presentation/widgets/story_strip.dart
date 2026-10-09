import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../../core/widgets/video_poster.dart';
import '../../../stories/stories.dart';
import '../../../stories/story_composer.dart';
import '../../../stories/story_viewer.dart';

/// Полоса историй над лентой: первой — «Ваша история» (нажатие смотрит, «+»
/// добавляет), дальше авторы; непросмотренные в цветной рамке и впереди.
class StoryStrip extends ConsumerWidget {
  const StoryStrip({super.key});

  static const _size = 76.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(storiesProvider).value ?? const <StoryGroup>[];
    final hasMine = groups.isNotEmpty && groups.first.isMine;
    final others = hasMine ? groups.skip(1).toList() : groups;
    final available = ref.watch(storiesRepositoryProvider).available;
    if (!available && groups.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: _size + 28,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
        children: [
          _MineTile(
            group: hasMine ? groups.first : null,
            onOpen: () => showStories(context, groups: groups, initialGroup: 0),
            onAdd: () => addStory(context, ref),
          ),
          for (final (i, group) in others.indexed) ...[
            const SizedBox(width: 12),
            _GroupTile(
              group: group,
              onTap: () => showStories(
                context,
                groups: groups,
                initialGroup: i + (hasMine ? 1 : 0),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Превью одной сторис в квадрате: фото, кадр видео или цветная плитка с текстом.
class StoryCover extends StatelessWidget {
  const StoryCover({super.key, required this.story});

  final Story story;

  @override
  Widget build(BuildContext context) {
    final label = story.sourceLabel;
    if (label == null) return _content();
    // Сторис из поста помечена мелко снизу: «статья», «маршрут», «пост».
    return Stack(
      fit: StackFit.expand,
      children: [
        _content(),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            color: Colors.black45,
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 9.5, height: 1.1),
            ),
          ),
        ),
      ],
    );
  }

  Widget _content() {
    switch (story.kind) {
      case StoryKind.photo:
        return Image(
          image: imageProviderFor(story.mediaUrl!),
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => ColoredBox(color: AppColors.ink2),
        );
      case StoryKind.video:
        return VideoPoster(url: story.mediaUrl!, showPlay: false);
      case StoryKind.text:
        return DecoratedBox(
          decoration: BoxDecoration(gradient: storyGradient(story.bg)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
            child: Center(
              child: Text(
                story.body ?? '',
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  // Мельче, чтобы длинное слово не рвалось посередине.
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  height: 1.15,
                ),
              ),
            ),
          ),
        );
    }
  }
}

class _Frame extends StatelessWidget {
  const _Frame({required this.color, required this.child});

  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: StoryStrip._size,
    height: StoryStrip._size,
    padding: const EdgeInsets.all(2.5),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: color, width: 1.6),
    ),
    child: ClipRRect(borderRadius: BorderRadius.circular(18), child: child),
  );
}

class _GroupTile extends StatelessWidget {
  const _GroupTile({required this.group, required this.onTap});

  final StoryGroup group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Блик: ${group.authorName}',
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: StoryStrip._size,
          child: Column(
            children: [
              _Frame(
                color: group.allViewed ? AppColors.hair : AppColors.primaryTint,
                child: StoryCover(story: group.cover),
              ),
              const SizedBox(height: 6),
              Text(
                group.authorName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: AppColors.textDim),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MineTile extends StatelessWidget {
  const _MineTile({required this.group, required this.onOpen, required this.onAdd});

  final StoryGroup? group;
  final VoidCallback onOpen;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final mine = group;
    final plus = Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: AppColors.primary,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.ink, width: 2),
      ),
      child: Icon(Icons.add, size: 15, color: AppColors.onPrimary),
    );

    return SizedBox(
      width: StoryStrip._size,
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Semantics(
                button: true,
                label: mine == null ? 'Добавить блик' : 'Ваш блик',
                child: GestureDetector(
                  onTap: mine == null ? onAdd : onOpen,
                  child: mine == null
                      ? _Frame(
                          color: AppColors.hair,
                          child: ColoredBox(
                            color: AppColors.ink2,
                            child: Icon(Icons.add_a_photo_outlined, color: AppColors.textDim),
                          ),
                        )
                      : _Frame(
                          color: mine.allViewed ? AppColors.hair : AppColors.primaryTint,
                          child: StoryCover(story: mine.cover),
                        ),
                ),
              ),
              if (mine != null)
                Positioned(
                  right: -4,
                  bottom: -4,
                  child: GestureDetector(
                    onTap: onAdd,
                    child: Semantics(button: true, label: 'Добавить блик', child: plus),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            mine == null ? 'Добавить' : 'Вы',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, color: AppColors.textDim),
          ),
        ],
      ),
    );
  }
}
