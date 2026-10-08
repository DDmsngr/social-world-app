import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:social_world/features/notifications/bell.dart';
import 'package:social_world/features/notifications/notification_prefs.dart';

void main() {
  group('NotificationPrefs', () {
    test('по умолчанию включены сообщения, комментарии, лайки и упоминания', () {
      const prefs = NotificationPrefs();
      expect(
        [for (final c in NotificationCategory.values) if (prefs.isOn(c)) c],
        [
          NotificationCategory.messages,
          NotificationCategory.comments,
          NotificationCategory.likes,
          NotificationCategory.mentions,
        ],
      );
    });

    test('в настройках хранится только отличие от умолчаний', () {
      var prefs = const NotificationPrefs()
          .withCategory(NotificationCategory.follows, true)
          .withCategory(NotificationCategory.likes, false);
      expect(prefs.overrides, {'follows': true, 'likes': false});
      expect(prefs.isOn(NotificationCategory.follows), isTrue);
      expect(prefs.isOn(NotificationCategory.likes), isFalse);

      // Вернули умолчание — запись исчезает.
      prefs = prefs.withCategory(NotificationCategory.likes, true);
      expect(prefs.overrides, {'follows': true});
    });

    test('тихие часы включаются парой границ и выключаются обеими', () {
      var prefs = const NotificationPrefs().withQuiet(23 * 60, 7 * 60);
      expect(prefs.hasQuietHours, isTrue);
      prefs = prefs.withQuiet(null, null);
      expect(prefs.hasQuietHours, isFalse);
    });
  });

  group('NotificationBell', () {
    late GoRouter router;

    setUp(() {
      router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('главная'))),
          GoRoute(path: '/notifications', builder: (_, _) => const Scaffold(body: Text('список'))),
        ],
      );
    });

    Future<ProviderContainer> pump(WidgetTester tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
            builder: (context, child) => Stack(
              children: [
                Positioned.fill(child: child!),
                NotificationBell(router: router),
              ],
            ),
          ),
        ),
      );
      return container;
    }

    testWidgets('до события колокольчика не нажать, после — появляется и ведёт к списку',
        (tester) async {
      final container = await pump(tester);
      final bell = find.byIcon(Icons.notifications_active);

      // Спрятан за краем и не принимает нажатий.
      final ignoring = tester.widget<IgnorePointer>(
        find.ancestor(of: bell, matching: find.byType(IgnorePointer)).first,
      );
      expect(ignoring.ignoring, isTrue);

      container.read(bellProvider.notifier).ping();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final shown = tester.widget<IgnorePointer>(
        find.ancestor(of: bell, matching: find.byType(IgnorePointer)).first,
      );
      expect(shown.ignoring, isFalse);

      await tester.tap(bell);
      await tester.pumpAndSettle();
      expect(find.text('список'), findsOneWidget);

      // Таймер скрытия не должен остаться висеть после теста.
      await tester.pump(NotificationBell.stay + const Duration(seconds: 1));
    });

    testWidgets('на экране уведомлений колокольчик не появляется', (tester) async {
      final container = await pump(tester);
      router.go('/notifications');
      await tester.pumpAndSettle();

      container.read(bellProvider.notifier).ping();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final state = tester.widget<IgnorePointer>(
        find
            .ancestor(
              of: find.byIcon(Icons.notifications_active),
              matching: find.byType(IgnorePointer),
            )
            .first,
      );
      expect(state.ignoring, isTrue);
    });
  });
}
