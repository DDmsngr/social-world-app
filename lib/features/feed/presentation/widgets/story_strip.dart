import 'package:flutter/material.dart';

import '../../../../core/media/photo_viewer.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../domain/entities/post.dart';

/// Одна «история»: свежее фото момента. Отдельной сущности в базе нет — это
/// проекция ленты, поэтому она не заводит второй источник правды.
class StoryItem {
  const StoryItem({
    required this.post,
    required this.photoUrl,
    required this.caption,
  });

  final Post post;
  final String photoUrl;
  final String caption;
}

/// Истории для полосы: последний снимок каждого автора, самые свежие первыми.
/// Статьи не входят — это тексты, а не быстрые моменты.
List<StoryItem> storiesFrom(List<Post> posts, {int limit = 20}) {
  final seenAuthors = <String>{};
  final items = <StoryItem>[];
  for (final post in posts) {
    if (post.isArticle || post.isRoute) continue;
    final photos = post.photoUrls;
    if (photos.isEmpty || !seenAuthors.add(post.authorId)) continue;

    final text = post.body?.trim() ?? '';
    items.add(
      StoryItem(
        post: post,
        photoUrl: photos.first,
        caption: text.isEmpty ? post.authorName : '${post.authorName}: $text',
      ),
    );
    if (items.length >= limit) break;
  }
  return items;
}

/// Полоса историй над лентой. Открыть историю — два нажатия: вкладка
/// «Моменты», затем превью. Превью — квадрат со скруглёнными углами в
/// бордовой рамке.
class StoryStrip extends StatelessWidget {
  const StoryStrip({super.key, required this.stories});

  final List<StoryItem> stories;

  static const _size = 76.0;

  @override
  Widget build(BuildContext context) {
    if (stories.isEmpty) return const SizedBox.shrink();

    final urls = [for (final story in stories) story.photoUrl];
    final captions = [for (final story in stories) story.caption];

    return SizedBox(
      height: _size + 28,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
        itemCount: stories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final story = stories[index];
          return Semantics(
            button: true,
            label: 'История: ${story.post.authorName}',
            child: GestureDetector(
              onTap: () => showPhotoViewer(
                context,
                urls: urls,
                captions: captions,
                initialIndex: index,
              ),
              child: SizedBox(
                width: _size,
                child: Column(
                  children: [
                    Container(
                      width: _size,
                      height: _size,
                      padding: const EdgeInsets.all(2.5),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: AppColors.primaryTint, width: 1.6),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: Image(
                          image: imageProviderFor(story.photoUrl),
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              ColoredBox(color: AppColors.ink2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      story.post.authorName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: AppColors.textDim),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
