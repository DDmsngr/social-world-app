import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:social_world/features/discover/domain/entities/city.dart';
import 'package:social_world/features/discover/presentation/providers/city_provider.dart';
import 'package:social_world/features/discover/presentation/providers/discover_providers.dart';
import 'package:social_world/features/discover/presentation/widgets/city_picker.dart';

// Путь «открыл выбор города → выбрал → карта поехала» на телефоне не
// проверить: ввод через adb на Xiaomi заблокирован, а в вебе карты нет.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<ProviderContainer> pumpPicker(WidgetTester tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showCityPicker(context),
                child: const Text('открыть'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('открыть'));
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('по умолчанию выбран пилотный город', (tester) async {
    final container = await pumpPicker(tester);
    expect(container.read(cityProvider), Cities.sochi);
  });

  testWidgets('выбор города меняет центр карты', (tester) async {
    final container = await pumpPicker(tester);

    await tester.tap(find.text('Краснодар'));
    await tester.pumpAndSettle();

    expect(container.read(cityProvider).id, 'krasnodar');
    final center = await container.read(discoverCenterProvider.future);
    expect(center.latitude, closeTo(45.0355, 0.0001));
    expect(center.longitude, closeTo(38.9753, 0.0001));
  });

  testWidgets('выбор города сохраняется между запусками', (tester) async {
    await pumpPicker(tester);
    // Список прокручиваемый и ленивый — до Казани добираемся поиском, как
    // это и сделал бы человек.
    await tester.enterText(find.byType(TextField), 'Казань');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Казань'));
    await tester.pumpAndSettle();

    // Следующий запуск читает город из хранилища до первого кадра.
    expect((await loadCity()).id, 'kazan');
  });

  testWidgets('поиск сужает список, лишние города пропадают', (tester) async {
    await pumpPicker(tester);
    expect(find.widgetWithText(ListTile, 'Москва'), findsOneWidget);

    // Ищем по ListTile: набранное в поле слово — тоже Text на экране.
    await tester.enterText(find.byType(TextField), 'Сочи');
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ListTile, 'Сочи'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Москва'), findsNothing);
  });

  testWidgets('города, которого нет, не выдают за пустой список', (tester) async {
    await pumpPicker(tester);

    await tester.enterText(find.byType(TextField), 'Атлантида');
    await tester.pumpAndSettle();

    expect(find.text('Такого города пока нет в списке'), findsOneWidget);
  });
}
