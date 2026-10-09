import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:social_world/core/router/app_router.dart';
import 'package:social_world/features/create/presentation/compose_screen.dart';
import 'package:social_world/features/create/presentation/create_screen.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('вид формы берётся из адреса, незнакомый — обычный момент', () {
    expect(ComposeKind.fromSegment('article'), ComposeKind.article);
    expect(ComposeKind.fromSegment('event'), ComposeKind.event);
    expect(ComposeKind.fromSegment('moment'), ComposeKind.moment);
    expect(ComposeKind.fromSegment('что-то'), ComposeKind.moment);
    expect(ComposeKind.fromSegment(null), ComposeKind.moment);
  });

  testWidgets('вкладка «+» — выбор из шести вариантов, каждый ведёт на свой экран',
      (tester) async {
    final opened = <String>[];
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const CreateScreen()),
        GoRoute(
          path: '/:rest(.*)',
          builder: (_, state) {
            opened.add(state.uri.path);
            return const Scaffold(body: Text('экран'));
          },
        ),
      ],
    );
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pump();

    for (final title in ['Момент', 'Статья', 'Маршрут', 'Событие', 'Квест', 'Мне надо']) {
      expect(find.text(title), findsOneWidget, reason: title);
    }

    final expected = {
      'Момент': '${Routes.compose}/moment',
      'Статья': '${Routes.compose}/article',
      'Маршрут': Routes.routeRecorder,
      'Событие': '${Routes.compose}/event',
      'Квест': Routes.createQuest,
      'Мне надо': Routes.createNeed,
    };
    for (final entry in expected.entries) {
      await tester.tap(find.text(entry.key));
      await tester.pumpAndSettle();
      expect(opened.last, entry.value, reason: entry.key);
      router.pop();
      await tester.pumpAndSettle();
    }
  });
}
