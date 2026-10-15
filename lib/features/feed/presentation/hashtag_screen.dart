import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/text/hashtags.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/state_message.dart';
import 'providers/feed_providers.dart';
import 'providers/muted_hashtags.dart';
import 'widgets/post_card.dart';

/// Лента одного хэштега: все видимые мне посты с ним, новые сверху.
class HashtagScreen extends ConsumerWidget {
  const HashtagScreen({super.key, required this.tag});

  final String tag;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posts = ref.watch(hashtagFeedProvider(tag));
    final muted = ref.watch(mutedHashtagsProvider).contains(normalizeHashtag(tag));

    return Scaffold(
      appBar: AppBar(
        title: Text('#$tag'),
        leading: IconButton(
          onPressed: () => context.canPop() ? context.pop() : context.go(Routes.feed),
          tooltip: 'Назад',
          icon: const Icon(Icons.arrow_back),
        ),
        actions: [
          IconButton(
            tooltip: muted ? 'Снова показывать в ленте' : 'Не показывать в ленте',
            icon: Icon(muted ? Icons.visibility_off : Icons.visibility_outlined),
            onPressed: () {
              ref.read(mutedHashtagsProvider.notifier).toggle(tag);
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(
                    persist: false,
                    duration: const Duration(seconds: 3),
                    content: Text(
                      muted
                          ? 'Посты с #$tag снова в ленте'
                          : 'Посты с #$tag больше не покажутся в ленте. Вернуть: Настройки → Скрытые теги',
                    ),
                  ),
                );
            },
          ),
        ],
      ),
      body: posts.when(
        loading: () => const LoadingView(),
        error: (_, _) => StateMessage.error(
          onAction: () => ref.invalidate(hashtagFeedProvider(tag)),
        ),
        data: (list) => list.isEmpty
            ? StateMessage(
                title: 'Пока ничего',
                text: 'С тегом #$tag ещё никто не публиковал. Можно начать первым.',
                icon: Icons.tag,
              )
            : RefreshIndicator(
                onRefresh: () async => ref.refresh(hashtagFeedProvider(tag).future),
                child: ListView.builder(
                  padding: AppSpacing.page(context),
                  itemCount: list.length + 1,
                  itemBuilder: (context, index) => index == 0
                      ? Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            '${list.length} ${_posts(list.length)}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        )
                      : PostCard(post: list[index - 1]),
                ),
              ),
      ),
    );
  }
}

String _posts(int n) {
  final r = n % 100;
  if (r >= 11 && r <= 14) return 'публикаций';
  return switch (n % 10) {
    1 => 'публикация',
    2 || 3 || 4 => 'публикации',
    _ => 'публикаций',
  };
}
