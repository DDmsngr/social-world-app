import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:social_world/core/router/app_router.dart';
import 'package:social_world/features/auth/domain/entities/app_user.dart';
import 'package:social_world/features/auth/presentation/providers/auth_providers.dart';
import 'package:social_world/features/stories/stories.dart';
import 'package:social_world/features/stories/story_viewer.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('тап по аватару или имени автора блика — его профиль, просмотр закрывается', (tester) async {
    final story = Story(
      id: 's1',
      authorId: 'author-1',
      authorName: 'Вика',
      kind: StoryKind.text,
      body: 'привет',
      createdAt: DateTime.now(),
    );
    final group = StoryGroup(authorId: 'author-1', authorName: 'Вика', stories: [story], isMine: false);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showStories(context, groups: [group], initialGroup: 0),
                child: const Text('открыть'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '${Routes.user}/:id',
          builder: (_, state) => Scaffold(body: Text('профиль ${state.pathParameters['id']}')),
        ),
      ],
    );
    addTearDown(router.dispose);
    final container = ProviderContainer(
      overrides: [
        currentUserProvider.overrideWithValue(const AppUser(id: 'me')),
        storiesRepositoryProvider.overrideWithValue(StoriesRepository(null)),
      ],
    );
    addTearDown(container.dispose);
    // Лента бликов уже загружена — как в приложении, когда блик открывают из неё.
    await tester.runAsync(() => container.read(storiesProvider.future));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.tap(find.text('открыть'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const Key('story-author')), findsOneWidget);

    await tester.tap(find.byKey(const Key('story-author')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('профиль author-1'), findsOneWidget);
    expect(find.byKey(const Key('story-author')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
