import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:social_world/features/auth/domain/entities/app_user.dart';
import 'package:social_world/features/auth/presentation/providers/auth_providers.dart';
import 'package:social_world/features/discover/domain/entities/city.dart';
import 'package:social_world/features/discover/presentation/providers/city_provider.dart';
import 'package:social_world/features/feed/presentation/feed_screen.dart';
import 'package:social_world/features/feed/presentation/providers/feed_providers.dart';

// «Моменты: Страна | Город» (п. 47 ТЗ): по умолчанию страна, город — тот же,
// что выбран на Pulse.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<ProviderContainer> pump(WidgetTester tester, City city) async {
    final container = ProviderContainer(
      overrides: [
        currentUserProvider.overrideWithValue(const AppUser(id: 'me', displayName: 'Я')),
        initialCityProvider.overrideWithValue(city),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: FeedScreen()),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('по умолчанию — страна', (tester) async {
    final container = await pump(tester, Cities.fallback);
    expect(container.read(feedScopeProvider), FeedScope.country);
    expect(container.read(feedCityFilterProvider), isNull);
    expect(find.text('Страна'), findsOne);
    expect(find.text(Cities.fallback.name), findsOne);
  });

  testWidgets('«Город» в пилотном городе показывает ленту', (tester) async {
    final container = await pump(tester, Cities.fallback);
    await tester.tap(find.text(Cities.fallback.name));
    await tester.pumpAndSettle();
    expect(container.read(feedCityFilterProvider), Cities.fallback.name);
    expect(find.text('Пока тихо'), findsNothing);
  });

  testWidgets('в городе без моментов — пусто и путь обратно', (tester) async {
    final other = Cities.all.firstWhere((c) => c != Cities.fallback);
    await pump(tester, other);
    await tester.tap(find.text(other.name));
    await tester.pumpAndSettle();
    expect(find.text('Пока тихо'), findsOne);

    await tester.tap(find.text('Вся страна'));
    await tester.pumpAndSettle();
    expect(find.text('Пока тихо'), findsNothing);
  });
}
